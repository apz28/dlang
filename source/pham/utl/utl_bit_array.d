/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2020 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.bit_array;

import core.bitop : bsf, popcnt;
import std.algorithm.comparison : min;
import std.bitmanip : bigEndianToNative, littleEndianToNative, nativeToBigEndian, nativeToLittleEndian, swapEndian;
import std.format : FormatSpec;
import std.range.primitives : isOutputRange, put;
import std.system : Endian;
import std.traits : isIntegral, isNumeric, isSomeChar, isUnsigned, Unqual;

import pham.utl.object : cmpInteger;
import pham.utl.utf8 : ShortStringBuffer;

nothrow @safe:

union Map16Bit
{
    ushort u; // Make this first to have zero initialized value
    short i;
    ubyte[2] lh;
    ubyte[ushort.sizeof] a;
}
static assert(Map16Bit.sizeof == 2);

union Map32Bit
{
    uint u; // Make this first to have zero initialized value
    int i;
    float f;
    ushort[2] lh;
    ubyte[uint.sizeof] a;
}
static assert(Map32Bit.sizeof == 4);

union Map64Bit
{
    ulong u; // Make this first to have zero initialized value
    long i;
    double f;
    uint[2] lh;
    ubyte[ulong.sizeof] a;
}
static assert(Map64Bit.sizeof == 8);

pragma(inline, true)
private size_t bitAt(T)(const(size_t) index) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    return index & (T.sizeof * 8 - 1);
}

pragma(inline, true)
private size_t elementAt(T)(const(size_t) index) @nogc pure
if (isUnsigned!T && T.sizeof <= 8)
{
    return index / (T.sizeof * 8);
}

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
T bytesToNative(T)(scope const(ubyte)[] bytes) @nogc pure
if (isIntegral!T)
in
{
    assert(bytes.length >= T.sizeof);
}
do
{
    ubyte[T.sizeof] convertingBytes = bytes[0..T.sizeof];
    version (LittleEndian)
        return littleEndianToNative!T(convertingBytes);
    else
        return bigEndianToNative!T(convertingBytes);
}

pragma(inline, true)
T bytesToNative(T)(scope const(ubyte)[] bytes, const(Endian) endianness) @nogc pure
if (isIntegral!T)
in
{
    assert(bytes.length >= T.sizeof);
}
do
{
    ubyte[T.sizeof] convertingBytes = bytes[0..T.sizeof];
    return endianness == Endian.littleEndian
        ? littleEndianToNative!T(convertingBytes)
        : bigEndianToNative!T(convertingBytes);
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

    version (none)
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

pragma(inline, true)
T hostToNetworkOrder(T)(const(T) host) @nogc pure
if (isIntegral!T || isSomeChar!T)
{
    version (BigEndian)
        return host;
    else
        return swapEndian(host);
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

    version (none)
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

pragma(inline, true)
auto nativeToBytes(T)(const(T) value) @nogc pure
if (isIntegral!T)
{
    version (LittleEndian)
        return nativeToLittleEndian!T(value);
    else
        return nativeToBigEndian!T(value);
}

pragma(inline, true)
auto nativeToBytes(T)(const(T) value, const(Endian) endianness) @nogc pure
if (isIntegral!T)
{
    return endianness == Endian.littleEndian
        ? nativeToLittleEndian!T(value)
        : nativeToBigEndian!T(value);
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
        static assert(0, "Unsupport unsigned type");
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

struct BitArrayImpl(T)
if (isUnsigned!T)
{
nothrow @safe:
    alias UnqualThis = Unqual!(BitArrayImpl!T);

public:
    enum bitsPerByte = 8;
    enum bitsPerElement = T.sizeof * bitsPerByte;

public:
    /*
     * Allocates space to hold length bit values. All of the values in the bit
     * array are set to 0.
     */
    this(size_t length) pure
    {
        this(length, false);
    }

    /*
     * Allocates space to hold length bit values. All of the values in the bit
     * array are set to defaultValue.
     */
    this(size_t length, bool bit) pure
    {
        this._length = length;
        this._values.length = bitLengthToElement!T(length);
        if (length)
            setAll(bit);
    }

    this(scope const(bool)[] bits) pure
    {
        const bitLength = bits.length;
        this._length = bitLength;
        this._values.length = bitLengthToElement!T(bitLength);
        foreach (i, bit; bits)
        {
            if (bit)
                this._values[i / bitsPerElement] |= (cast(T)1 << (i % bitsPerElement));
        }
    }

    this(scope const(T)[] values) pure
    {
        this._length = values.length * bitsPerElement;
        this._values = values.dup;
    }

    /*
     * Allocates space to hold the bit values in bytes. ubytes[0] represents
     * bits 0 - 7, ubytes[1] represents bits 8 - 15, etc. The LSB of each ubyte
     * represents the lowest index value; ubytes[0] & 1 represents bit 0,
     * ubytes[0] & 2 represents bit 1, ubytes[0] & 4 represents bit 2, etc.
     */
    static if (!is(T == ubyte))
    this(scope const(ubyte)[] bytes) pure
    {
        const bitLength = bytes.length * bitsPerByte;
        this._length = bitLength;
        this._values.length = bitLengthToElement!T(bitLength);

        if (bitLength)
        {
            size_t i, j;
            while (j + T.sizeof <= bytes.length)
            {
                static if (T.sizeof == 2)
                {
                    _values[i++] = bytes[j] | (cast(T)(bytes[j + 1]) << 8);
                }
                else static if (T.sizeof == 4)
                {
                    _values[i++] = bytes[j]
                        | (cast(T)(bytes[j + 1]) << 8)
                        | (cast(T)(bytes[j + 2]) << 16)
                        | (cast(T)(bytes[j + 3]) << 24);
                }
                else
                {
                    _values[i++] = bytes[j]
                        | (cast(T)(bytes[j + 1]) << 8)
                        | (cast(T)(bytes[j + 2]) << 16)
                        | (cast(T)(bytes[j + 3]) << 24)
                        | (cast(T)(bytes[j + 4]) << 32)
                        | (cast(T)(bytes[j + 5]) << 40)
                        | (cast(T)(bytes[j + 6]) << 48)
                        | (cast(T)(bytes[j + 7]) << 56);
                }

                j += T.sizeof;
            }

            // Remaining bytes
            switch (bytes.length - j)
            {
                static if (T.sizeof >= 8)
                {
                case 7:
                    _values[i] = (cast(T)(bytes[j + 2]) << 48);
                    goto case 6;
                case 6:
                    _values[i] = (cast(T)(bytes[j + 2]) << 40);
                    goto case 5;
                case 5:
                    _values[i] = (cast(T)(bytes[j + 2]) << 32);
                    goto case 4;
                case 4:
                    _values[i] = (cast(T)(bytes[j + 2]) << 24);
                    goto case 3;
                }

                static if (T.sizeof >= 4)
                {
                case 3:
                    _values[i] = (cast(T)(bytes[j + 2]) << 16);
                    goto case 2;
                case 2:
                    _values[i] |= (cast(T)(bytes[j + 1]) << 8);
                    goto case 1;
                }

                case 1:
                    _values[i] |= bytes[j];
                    break;
                default:
                    break;
            }
        }
    }

    this(this) pure
    {
        this._values = _values.dup;
    }

    /*
     * Support for `foreach` loop for `BitArray`.
     */
    int opApply(scope int delegate(bool) nothrow @trusted dg) const
    {
        foreach (i; 0..length)
        {
            if (const r = dg(opIndex(i)))
                return r;
        }
        return 0;
    }

    ///ditto
    int opApply(scope int delegate(size_t, bool) nothrow @trusted dg) const
    {
        foreach (i; 0..length)
        {
            if (const r = dg(i, opIndex(i)))
                return r;
        }
        return 0;
    }

    ref typeof(this) opOpAssign(string op)(const ref typeof(this) other) @nogc pure return
    if (op == "-" || op == "&" || op == "|" || op == "^")
    in
    {
        assert(other.length == length);
    }
    do
    {
        foreach (i, ref e; _values)
        {
            static if (op == "-")
                e &= ~other._values[i];
            else
                mixin("e " ~ op ~ "= other._values[i];");
        }
        clearUnusedHighBits();

        return this;
    }

    ref typeof(this) opOpAssign(string op)(const ref typeof(this) other) pure return
    if (op == "~" || op == "+")
    {
        // TODO optimize using fullword assignment
        const oldLength = length;
        length = oldLength + other.length;
        foreach (i; 0..other.length)
            this[oldLength + i] = other[i];
        return this;
    }

    ref typeof(this) opOpAssign(string op)(bool bit) pure return
    if (op == "~" || op == "+")
    {
        const oldLength = length;
        length = oldLength + 1;
        this[oldLength] = bit;
        return this;
    }

    /**
     * Operator `<<=` support.
     *
     * Shifts all the bits in the array to the left by the given number of
     * bits.  The leftmost bits are dropped, and 0's are appended to the end
     * to fill up the vacant bits.
     *
     * $(RED Warning: unused bits in the final word up to the next word
     * boundary may be overwritten by this operation. It does not attempt to
     * preserve bits past the end of the array.)
     */
    ref typeof(this) opOpAssign(string op)(size_t nBits) @nogc pure return
    if (op == "<<")
    {
        if (length)
        {
            const dim = bitLengthToElement!T(length);
            const size_t wordsToShift = nBits / bitsPerElement;
            const size_t bitsToShift = nBits % bitsPerElement;

            if (wordsToShift < dim)
            {
                foreach_reverse (i; 1..dim - wordsToShift)
                    _values[i + wordsToShift] = rollLeft(_values[i], _values[i - 1], bitsToShift);
                _values[wordsToShift] = rollLeft(_values[0], 0, bitsToShift);
            }

            foreach (i; 0..min(wordsToShift, dim))
                _values[i] = 0;
        }

        return this;
    }

    /**
     * Operator `>>=` support.
     *
     * Shifts all the bits in the array to the right by the given number of
     * bits.  The rightmost bits are dropped, and 0's are inserted at the back
     * to fill up the vacant bits.
     *
     * $(RED Warning: unused bits in the final word up to the next word
     * boundary may be overwritten by this operation. It does not attempt to
     * preserve bits past the end of the array.)
     */
    ref typeof(this) opOpAssign(string op)(size_t nBits) @nogc pure return
    if (op == ">>")
    {
        if (length)
        {
            const dim = bitLengthToElement!T(length);
            const size_t wordsToShift = nBits / bitsPerElement;
            const size_t bitsToShift = nBits % bitsPerElement;

            if (wordsToShift + 1 < dim)
            {
                foreach (i; 0..dim - wordsToShift - 1)
                    _values[i] = rollRight(_values[i + wordsToShift + 1],
                                          _values[i + wordsToShift],
                                          bitsToShift);
            }

            // The last word needs some care, as it must shift in 0's from past the
            // end of the array.
            if (wordsToShift < dim)
            {
                if (bitsToShift == 0)
                    _values[dim - wordsToShift - 1] = _values[dim - 1];
                else
                {
                    // Special case: if endBits == 0, then also endMask == 0.
                    const e = endBits;
                    const T lastWord = e
                        ? (_values[fullWords] & endMask(e))
                        : _values[fullWords - 1];
                    _values[dim - wordsToShift - 1] = rollRight(0, lastWord, bitsToShift);
                }
            }

            foreach (i; 0..min(wordsToShift, dim))
                _values[dim - i - 1] = 0;
        }

        return this;
    }

    /*
     * Support for binary bitwise operators for `BitArray`.
     */
    UnqualThis opBinary(string op)(const ref typeof(this) other) const pure
    if (op == "-" || op == "&" || op == "|" || op == "^")
    in
    {
        assert(other.length == length);
    }
    do
    {
        UnqualThis result = this.dup();
        return result.opOpAssign!op(other);
    }

    UnqualThis opBinary(string op)(const ref typeof(this) value) const pure
    if (op == "~" || op == "+")
    {
        UnqualThis result = this.dup();
        return result.opOpAssign!op(value);
    }

    UnqualThis opBinary(string op)(bool bit) const pure
    if (op == "~" || op == "+")
    {
        UnqualThis result = this.dup();
        result.length = length + 1;
        result[length] = bit;
        return result;
    }

    UnqualThis opBinaryRight(string op)(bool bit) const pure
    if (op == "~" || op == "+")
    {
        //TODO optimize fullword assignment
        UnqualThis result = UnqualThis(length + 1);
        result[0] = bit;
        foreach (i; 0..length)
            result[1 + i] = this[i];
        return result;
    }

    /*
     * Supports comparison operators for `BitArray`.
     */
    int opCmp(scope const(typeof(this)) rhs) const @nogc pure @trusted
    {
        const lesser = length < rhs.length ? &this : &rhs;
        const f = lesser.fullWords;
        const e = lesser.endBits;

        foreach (i; 0..f)
        {
            if (_values[i] != rhs._values[i])
                return _values[i] & (T(1) << bsf(_values[i] ^ rhs._values[i])) ? 1 : -1;
        }

        if (endBits)
        {
            const diff = _values[f] ^ rhs._values[f];
            if (diff)
            {
                const i = bsf(diff);
                if (i < e)
                    return _values[f] & (T(1) << i) ? 1 : -1;
            }
        }

        // Standard:
        // A bool value can be implicitly converted to any integral type,
        // with false becoming 0 and true becoming 1
        return cmpInteger(length, rhs.length);
    }

    /*
     * Support for operators == and != for `BitArray`.
     */
    bool opEquals(scope const(typeof(this)) rhs) const @nogc pure
    {
        if (length != rhs.length)
            return false;

        const f = fullWords;
        if (_values[0..f] != rhs._values[0..f])
            return false;

        const e = endBits;
        if (!e)
            return true;

        const m = endMask(e);
        return (_values[f] & m) == (rhs._values[f] & m);
    }

    /**
     * Returns the bit at the given index.
     */
    static if (is(T == ubyte))
    T[] opIndex() @nogc pure return
    {
        return _values;
    }

    /**
     * Returns the bit at the given index.
     */
    bool opIndex(const(size_t) index) const @nogc pure
    in
    {
        assert(index < length);
    }
    do
    {
        return bt(_values, index);
    }

    bool opIndexAssign(bool bit, const(size_t) index) @nogc pure @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        if (bit)
            bts(_values.ptr, index);
        else
            btr(_values.ptr, index);
        return bit;
    }

    /*
     * Sets all the values in the `BitArray` to the value specified by `bit`.
     */
    ref typeof(this) opSliceAssign(bool bit) @nogc return
    {
        if (length)
            setAll(bit);
        return this;
    }

    /**
      Sets the bits of a slice of `BitArray` starting
      at index `beginIndex` and ends at index ($D endIndex - 1)
      with the values specified by `bit`.
     */
    ref typeof(this) opSliceAssign(bool bit, const(size_t) beginIndex, const(size_t) endIndex) @nogc return
    in
    {
        assert(beginIndex <= endIndex, "beginIndex must be less or equal to endIndex");
        assert(endIndex <= length, "endIndex must be less or equal to the length");
    }
    do
    {
        size_t startBlock = beginIndex / bitsPerElement;
        const size_t endBlock = endIndex / bitsPerElement;
        const size_t startOffset = beginIndex % bitsPerElement;
        const size_t endOffset = endIndex % bitsPerElement;

        if (startBlock == endBlock)
        {
            const T startBlockMask = cast(T)(~((T(1) << startOffset) - 1));
            const T endBlockMask = cast(T)((T(1) << endOffset) - 1);
            const T joinMask = startBlockMask & endBlockMask;
            if (bit)
                _values[startBlock] |= joinMask;
            else
                _values[startBlock] &= joinMask.flip();
            return this;
        }

        if (startOffset != 0)
        {
            const T startBlockMask = cast(T)(~((T(1) << startOffset) - 1));
            if (bit)
                _values[startBlock] |= startBlockMask;
            else
                _values[startBlock] &= startBlockMask.flip();
            ++startBlock;
        }

        if (endOffset != 0)
        {
            const T endBlockMask = (T(1) << endOffset) - 1;
            if (bit)
                _values[endBlock] |= endBlockMask;
            else
                _values[endBlock] &= endBlockMask.flip();
        }

        _values[startBlock..endBlock] = cast(T)(T(0) - T(bit));

        return this;
    }

    /*
     * Support for unary operator ~ for `BitArray`.
     */
    UnqualThis opUnary(string op)() const pure
    if (op == "~")
    {
        UnqualThis result = UnqualThis(length);
        if (length)
        {
            foreach (i, e; _values)
                result._values[i] = ~e;
            result.clearUnusedHighBits();
        }
        return result;
    }

    /*
     * Counts all the set bits in the `BitArray`
     */
    size_t countBitSet() const @nogc pure
    {
        size_t result;
        if (length)
        {
            const f = fullWords;
            foreach (i; 0..f)
                result += popcnt(_values[i]);
            if (const e = endBits)
                result += popcnt(_values[f] & endMask(e));
        }
        return result;
    }

    UnqualThis dup() const pure
    {
        UnqualThis result = UnqualThis(this._values);
        result._length = length; // Should be OK because we maintain this.values
        return result;
    }

    /*
     * Flips all the bits in the `BitArray`
     */
    ref typeof(this) flip() @nogc pure return
    {
        if (length)
        {
            foreach (ref e; _values)
                e = e.flip();
            clearUnusedHighBits();
        }
        return this;
    }

    /**
     * Flips a single bit, specified by `index` and return original value
     */
    bool flip(size_t index) @nogc pure @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        auto result = bt(_values, index);
        if (result)
            btr(_values.ptr, index);
        else
            bts(_values.ptr, index);
        return result;
    }

    U[] get(U)() const pure @trusted
    if (is(U == bool) || is(U == ubyte) || is(Unqual!U == T))
    {
        static if (is(U == bool))
        {
            bool[] result = new bool[](length);
            foreach (i; 0..length)
                result[i] = bt(_values.ptr, i);
            return result;
        }
        else static if (is(Unqual!U == T))
            return _values.dup;
        else //static if (is(T == ubyte))
        {
            ubyte[] result = new ubyte[](bitLengthToElement!ubyte(length));
            foreach (i; 0..result.length)
                // Shift to bring the required byte to LSB, then mask
                result[i] = cast(ubyte)((_values[i / T.sizeof] >> ((i % T.sizeof) * 8)) & 0xff);
            return result;
        }
    }

    ref typeof(this) not() @nogc pure return
    {
        return flip();
    }

    /*
     * Reverses the bits of the `BitArray`.
     */
    ref typeof(this) reverse() @nogc pure return
    {
        if (length < 2)
            return this;

        size_t lo = 0;
        size_t hi = length - 1;
        for (; lo < hi; lo++, hi--)
        {
            const bool t = this[lo];
            this[lo] = this[hi];
            this[hi] = t;
        }

        return this;
    }

    size_t toHash() const @nogc pure @trusted
    {
        if (length)
        {
            const fullBytes = length / 8;

            size_t result = 3557;

            foreach (i; 0..fullBytes)
            {
                result *= 3559;
                result += (cast(ubyte*)_values.ptr)[i];
            }

            foreach (i; (8 * fullBytes)..length)
            {
                result *= 3571;
                result += this[i];
            }

            return result;
        }
        else
            return 0;
    }

    string toString() const
    {
        FormatSpec!char f; // default spec=%s
        ShortStringBuffer!char buffer;
        return toString(buffer, f).toString();
    }

    /*
     * Return a string representation of this BitArray.
     *
     * Two format specifiers are supported:
     * $(LI $(B %s) which prints the bits as an array, and)
     * $(LI $(B %b) which prints the bits as 8-bit byte packets)
     * separated with an underscore.
     *
     * Params:
     *     sink = A `char` accepting
     *     $(REF_ALTTEXT output range, isOutputRange, std, range, primitives).
     *     fmt = A $(REF FormatSpec, std,format) which controls how the data
     *     is displayed.
     */
    ref Writer toString(Writer, Char)(return ref Writer sink, scope const ref FormatSpec!Char fmt) const
    if (isOutputRange!(Writer, Char) && isSomeChar!Char)
    {
        const spec = fmt.spec;
        switch (spec)
        {
            case 'b':
                return toBitString(sink);
            case 's':
                return toBitArray(sink);
            default:
                version (Debug)
                    assert(0);
                else
                    return toBitArray(sink);
        }
    }

    /*
     * Returns:
     *  Number of bits in the `BitArray`.
     */
    pragma(inline, true)
    @property size_t length() const @nogc pure scope
    {
        return _length;
    }

    /*
     * Sets the amount of bits in the `BitArray`.
     */
    @property size_t length(const(size_t) newLength) pure
    {
        if (_length != newLength)
        {
            const oldSize = bitLengthToElement!T(length);
            const newSize = bitLengthToElement!T(newLength);
            if (oldSize != newSize)
            {
                _values.length = newSize;
                // assumeSafeAppend does not support pure
                //() @trusted { values.assumeSafeAppend(); } ();
                if (newSize > oldSize)
                    _values[oldSize..newSize] = 0;
            }

            if (_length < newLength)
                clearUnusedHighBits();

            _length = newLength;
        }

        return newLength;
    }

private:
    // clear high bit values in the last element
    pragma(inline, true);
    void clearUnusedHighBits() @nogc pure
    {
        if (const e = endBits)
            _values[fullWords] &= endMask(e);
    }

    // Bit mask to extract the bits after the last full word
    pragma(inline, true);
    static T endMask(size_t endBits) @nogc pure
    {
        return cast(T)((T(1) << endBits) - 1);
    }

    // Rolls double word (upper, lower) to the left by nBits and returns the
    // upper word of the result.
    static T rollLeft(T upper, T lower, size_t nBits) @nogc pure
    {
        return nBits == 0
            ? upper
            : cast(T)(upper << nBits) | cast(T)(lower >> (bitsPerElement - nBits));
    }

    // Rolls double word (upper, lower) to the right by nBits and returns the
    // lower word of the result.
    static T rollRight(T upper, T lower, size_t nBits) @nogc pure
    {
        return nBits == 0
            ? lower
            : cast(T)(upper << (bitsPerElement - nBits)) | cast(T)(lower >> nBits);
    }

    void setAll(bool value) @nogc pure
    {
        _values[] = value ? T.max : 0u;
        if (value)
            clearUnusedHighBits();
    }

    ref Writer toBitArray(Writer)(return ref Writer sink) const pure
    {
        put(sink, '[');
        foreach (i; 0..length)
        {
            if (i)
                put(sink, ',');
            put(sink, cast(char)(this[i] + '0'));
        }
        put(sink, ']');

        return sink;
    }

    ref Writer toBitString(Writer)(return ref Writer sink) const pure
    {
        if (!length)
            return sink;

        const leftOver = length % bitsPerByte;

        foreach (i; 0..leftOver)
            put(sink, cast(char)(this[i] + '0'));

        if (leftOver && length > bitsPerByte)
            put(sink, '_');

        size_t count;
        foreach (i; leftOver..length)
        {
            put(sink, cast(char)(this[i] + '0'));
            if (++count == bitsPerByte && i != length - 1)
            {
                put(sink, '_');
                count = 0;
            }
        }

        return sink;
    }

    // Number of bits after the last full word
    pragma(inline, true)
    @property size_t endBits() const @nogc pure
    {
        return _length % bitsPerElement;
    }

    // The result can cause out of bound if endBits returns 0
    pragma(inline, true)
    @property size_t fullWords() const @nogc pure
    {
        return _length / bitsPerElement;
    }

private:
    size_t _length;
    T[] _values;
}

alias BitArray = BitArrayImpl!size_t;

// Any below codes are private
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

version (unittest)
{
    void checkBitArrayRange(ref BitArray b, size_t start, size_t end, bool v,
        size_t callerLine = __LINE__)
    {
        import pham.utl.test;

        foreach (i; start..end)
        {
            assert(b[i] == v, "BitDifference(" ~ dgToStr(callerLine) ~ "): at index " ~ dgToStr(i));
        }
    }

    static string toBitArray(ref BitArray b)
    {
        import std.format : format;

        scope (failure) assert(0);

        return format("%s", b);
    }

    static string toBitString(ref BitArray b)
    {
        import std.format : format;

        scope (failure) assert(0);

        return format("%b", b);
    }
}

@safe unittest // bitAt & elementAt
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.bitAt & elementAt");

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

@safe unittest // flip
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.flip");

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

@system unittest // bt
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bt");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.btc");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.btr & bts");

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

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray");

    auto b = BitArray(1, true);
    assert(b.length == 1);
    assert(b[0] == true);

    bool[] boolInput = [true, false, false, true, true];
    b = BitArray(boolInput);
    assert(b.length == boolInput.length);
    foreach (i; 0..boolInput.length)
    {
        assert(b[i] == boolInput[i]);
    }

    ubyte[] byteInput = [9, 0b101, 123, 255, 7];
    b = BitArray(byteInput);
    assert(b.length == byteInput.length * BitArray.bitsPerByte);
    foreach (i; 0..byteInput.length * BitArray.bitsPerByte)
    {
        auto ithBit = cast(bool)(byteInput[i / BitArray.bitsPerByte] & (1 << (i % BitArray.bitsPerByte)));
        assert(b[i] == ithBit);
    }

    size_t[] elementInput = [1, 0b101, 3, 3424234, 724398, 230947, 389492];
    b = BitArray(elementInput);
    assert(b.length == elementInput.length * BitArray.bitsPerElement);
    foreach (i; 0..elementInput.length * BitArray.bitsPerElement)
    {
        auto ithBit = cast(bool)(elementInput[i / BitArray.bitsPerElement] & (1L << (i % BitArray.bitsPerElement)));
        assert(b[i] == ithBit);
    }
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.length");

    BitArray ba;

    ba.length = 1;
    ba[0] = 1;
    ba.length = 0;
    ba.length = 1;
    assert(ba[0] == 0);

    ba.length = 2;
    ba[1] = 1;
    ba.length = 1;
    ba.length = 2;
    assert(ba[1] == 0);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.opIndex");

    static void fun(const(BitArray) arr)
    {
        auto x = arr[0];
        assert(x == 1);
    }

    BitArray a;
    a.length = 3;
    a[0] = 1;
    fun(a);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.opSliceAssign");

    auto b = BitArray(cast(bool[])[1,0,1,0,1,1]);

    // all bits are set
    b[] = true;
    assert(b.countBitSet() == 6);

    // none of the bits are set
    b[] = false;
    assert(b.countBitSet() == 0);

    b = BitArray(cast(bool[])[1,0,0,0,1,1,0]);
    b[1..3] = true;
    assert(b.countBitSet() == 5);
    checkBitArrayRange(b, 0, 3, true);

    bool[72] bitArray;
    b = BitArray(bitArray);
    b[63..67] = true;
    assert(b.countBitSet() == 4);
    assert(b[62] == false);
    checkBitArrayRange(b, 63, 67, true);
    assert(b[67] == false);
    b[63..67] = false;
    assert(b.countBitSet() == 0);

    b[0..64] = true;
    checkBitArrayRange(b, 0, 64, true);
    b[0..64] = false;
    assert(b.countBitSet() == 0);
    checkBitArrayRange(b, 0, 64, false);

    bool[256] bitArray2;
    b = BitArray(bitArray2);
    b[3..245] = true;
    checkBitArrayRange(b, 3, 245, true);
    b[3..245] = false;
    assert(b.countBitSet() == 0);
    checkBitArrayRange(b, 3, 245, false);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.flip");

    // positions 0, 2, 4 are set; after flipping, positions 1, 3, 5 are set
    auto b = BitArray(cast(bool[])[1,0,1,0,1,0]);
    b.flip();
    assert(b.countBitSet() == 3);
    assert(b[1] == true);
    assert(b[3] == true);
    assert(b[5] == true);

    bool[270] bits270;
    b = BitArray(bits270);
    b.flip();
    assert(b.countBitSet() == 270);
    checkBitArrayRange(b, 0, 270, true);

    b = BitArray(cast(bool[])[1,0,0,1]);
    b.flip(0);
    assert(b[0] == 0);
    assert(b[1] == 0);

    bool[200] bits200;
    bits200[90..130] = true;
    b = BitArray(bits200);
    b.flip(100);
    assert(b[99] == true);
    assert(b[100] == false);
    assert(b[101] == true);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.countBitSet");

    auto a = BitArray(cast(bool[])[0,1,1,0,0,1,1]);
    assert(a.countBitSet == 4);

    BitArray b;
    assert(b.countBitSet == 0);

    bool[200] boolArray;
    boolArray[45..130] = true;
    auto c = BitArray(boolArray);
    assert(c.countBitSet == 130 - 45);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.opApply");

    bool[] ba = [1,0,1];
    auto a = BitArray(ba);

    int i;
    foreach (b; a)
    {
        switch (i)
        {
            case 0: assert(b == true); break;
            case 1: assert(b == false); break;
            case 2: assert(b == true); break;
            default: assert(0);
        }
        i++;
    }
    assert(i == 3);

    foreach (j, b; a)
    {
        switch (j)
        {
            case 0: assert(b == true); break;
            case 1: assert(b == false); break;
            case 2: assert(b == true); break;
            default: assert(0);
        }
    }
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.reverse");

    bool[5] data = [1,0,1,1,0];
    auto b = BitArray(data);
    b.reverse();
    foreach (i; 0..data.length)
        assert(b[i] == data[4 - i]);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.opEquals");

    bool[] ba = [1,0,1,0,1];
    bool[] bb = [1,0,1];
    bool[] bc = [1,0,1,0,1,0,1];
    bool[] bd = [1,0,1,1,1];
    bool[] be = [1,0,1,0,1];
    bool[] bf = [1,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
    bool[] bg = [1,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1];

    auto a = BitArray(ba);
    auto b = BitArray(bb);
    auto c = BitArray(bc);
    auto d = BitArray(bd);
    auto e = BitArray(be);
    auto f = BitArray(bf);
    auto g = BitArray(bg);

    assert(a != b);
    assert(a != c);
    assert(a != d);
    assert(a == e);
    assert(f != g);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.opCmp");

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1];
        bool[] bc = [1,0,1,0,1,0,1];
        bool[] bd = [1,0,1,1,1];
        bool[] be = [1,0,1,0,1];
        bool[] bf = [1,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1];
        bool[] bg = [1,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        auto c = BitArray(bc);
        auto d = BitArray(bd);
        auto e = BitArray(be);
        auto f = BitArray(bf);
        auto g = BitArray(bg);

        assert(a >  b);
        assert(a >= b);
        assert(a <  c);
        assert(a <= c);
        assert(a <  d);
        assert(a <= d);
        assert(a == e);
        assert(a <= e);
        assert(a >= e);
        assert(f <  g);
        assert(g <= g);
    }

    {
        bool[] v;
        foreach (i; 1..256)
        {
            v.length = i;
            v[] = false;
            auto x = BitArray(v);
            v[i - 1] = true;
            auto y = BitArray(v);
            assert(x < y);
            assert(x <= y);
        }

        BitArray a1, a2;

        for (size_t len = 4; len <= 256; len <<= 1)
        {
            a1.length = a2.length = len;
            a1[len - 2] = a2[len - 1] = true;
            assert(a1 > a2);
            a1[len - 2] = a2[len - 1] = false;
        }

        foreach (j; 1..a1.length)
        {
            a1[j - 1] = a2[j] = true;
            assert(a1 > a2);
            a1[j - 1] = a2[j] = false;
        }
    }
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.opUnary~");

    bool[] ba = [1,0,1,0,1];
    auto a = BitArray(ba);
    BitArray b = ~a;

    assert(b[0] != a[0]);
    assert(b[1] != a[1]);
    assert(b[2] != a[2]);
    assert(b[3] != a[3]);
    assert(b[4] != a[4]);
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.opBinary");

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        BitArray c = a & b;

        assert(c[0] == 1);
        assert(c[1] == 0);
        assert(c[2] == 1);
        assert(c[3] == 0);
        assert(c[4] == 0);
    }

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        BitArray c = a | b;

        assert(c[0] == 1);
        assert(c[1] == 0);
        assert(c[2] == 1);
        assert(c[3] == 1);
        assert(c[4] == 1);
    }

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        BitArray c = a ^ b;

        assert(c[0] == 0);
        assert(c[1] == 0);
        assert(c[2] == 0);
        assert(c[3] == 1);
        assert(c[4] == 1);
    }

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        BitArray c = a - b;

        assert(c[0] == 0);
        assert(c[1] == 0);
        assert(c[2] == 0);
        assert(c[3] == 0);
        assert(c[4] == 1);
    }

    {
        bool[] ba = [1,0];
        bool[] bb = [0,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        BitArray c;

        c = (a ~ b);
        assert(c.length == 5);
        assert(c[0] == 1);
        assert(c[1] == 0);
        assert(c[2] == 0);
        assert(c[3] == 1);
        assert(c[4] == 0);

        c = (a ~ true);
        assert(c.length == 3);
        assert(c[0] == 1);
        assert(c[1] == 0);
        assert(c[2] == 1);

        c = (false ~ a);
        assert(c.length == 3);
        assert(c[0] == 0);
        assert(c[1] == 1);
        assert(c[2] == 0);
    }
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.opOpAssign");

    {
        bool[] ba = [1,0,1,0,1,1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        BitArray c = a;
        c.length = 5;
        c &= b;

        assert(a[5] == 1);
        assert(a[6] == 0);
        assert(a[7] == 1);
        assert(a[8] == 0);
        assert(a[9] == 1);
    }

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        a &= b;

        assert(a[0] == 1);
        assert(a[1] == 0);
        assert(a[2] == 1);
        assert(a[3] == 0);
        assert(a[4] == 0);
    }

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        a |= b;

        assert(a[0] == 1);
        assert(a[1] == 0);
        assert(a[2] == 1);
        assert(a[3] == 1);
        assert(a[4] == 1);
    }

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        a ^= b;

        assert(a[0] == 0);
        assert(a[1] == 0);
        assert(a[2] == 0);
        assert(a[3] == 1);
        assert(a[4] == 1);
    }

    {
        bool[] ba = [1,0,1,0,1];
        bool[] bb = [1,0,1,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        a -= b;

        assert(a[0] == 0);
        assert(a[1] == 0);
        assert(a[2] == 0);
        assert(a[3] == 0);
        assert(a[4] == 1);
    }

    {
        bool[] ba = [1,0,1,0,1];

        auto a = BitArray(ba);
        BitArray b;
        b = (a ~= true);

        assert(a[0] == 1);
        assert(a[1] == 0);
        assert(a[2] == 1);
        assert(a[3] == 0);
        assert(a[4] == 1);
        assert(a[5] == 1);

        assert(b == a);
    }

    {
        bool[] ba = [1,0];
        bool[] bb = [0,1,0];

        auto a = BitArray(ba);
        auto b = BitArray(bb);
        BitArray c;
        c = (a ~= b);

        assert(a.length == 5);
        assert(a[0] == 1);
        assert(a[1] == 0);
        assert(a[2] == 0);
        assert(a[3] == 1);
        assert(a[4] == 0);

        assert(c == a);
    }

    {
        bool[] buf = new bool[64*3];
        buf[0 .. 64] = true;
        BitArray b = BitArray(buf);
        checkBitArrayRange(b, 0, 64, true);
        b <<= 64;
        checkBitArrayRange(b, 64, 128, true);

        buf = new bool[64*3];
        buf[64*2..64*3] = true;
        b = BitArray(buf);
        checkBitArrayRange(b, 64*2, 64*3, true);
        b >>= 64;
        checkBitArrayRange(b, 64, 128, true);
    }

    {
        import std.array : array;
        import std.range : repeat;

        immutable r = size_t.sizeof * 8;

        BitArray a = true.repeat(r / 2).array;
        a >>= 0;
        checkBitArrayRange(a, 0, r / 2, true);
        a >>= 1;
        checkBitArrayRange(a, 0, r / 2 - 1, true);

        BitArray b = true.repeat(r).array;
        b >>= 0;
        checkBitArrayRange(b, 0, r, true);
        b >>= 1;
        checkBitArrayRange(b, 0, r - 1, true);

        BitArray c = true.repeat(2 * r).array;
        c >>= 0;
        checkBitArrayRange(c, 0, 2 * r, true);
        assert(c.countBitSet() == 2 * r);
        c >>= 10;
        checkBitArrayRange(c, 0, 2 * r - 10, true);
        assert(c.countBitSet() == 2 * r - 10);
    }

    {
        auto b = BitArray(cast(const(bool)[])[1,1,0,0,1,0,1,0,1,1,0,1,1]);

        b <<= 1;
        assert(toBitString(b) == "01100_10101101");

        b >>= 1;
        assert(toBitString(b) == "11001_01011010");

        b <<= 4;
        assert(toBitString(b) == "00001_10010101");

        b >>= 5;
        assert(toBitString(b) == "10010_10100000");

        b <<= 13;
        assert(toBitString(b) == "00000_00000000");

        b = BitArray(cast(const(bool)[])[1,0,1,1,0,1,1,1]);
        b >>= 8;
        assert(toBitString(b) == "00000000");
    }

    {
        // This has to be long enough to occupy more than one size_t. On 64-bit
        // machines, this would be at least 64 bits.
        auto b = BitArray(cast(const(bool)[])[
            1, 0, 0, 0, 0, 0, 0, 0,  1, 1, 0, 0, 0, 0, 0, 0,
            1, 1, 1, 0, 0, 0, 0, 0,  1, 1, 1, 1, 0, 0, 0, 0,
            1, 1, 1, 1, 1, 0, 0, 0,  1, 1, 1, 1, 1, 1, 0, 0,
            1, 1, 1, 1, 1, 1, 1, 0,  1, 1, 1, 1, 1, 1, 1, 1,
            1, 0, 1, 0, 1, 0, 1, 0,  0, 1, 0, 1, 0, 1, 0, 1,
        ]);

        b <<= 8;
        assert(toBitString(b) ==
               "00000000_10000000_" ~
               "11000000_11100000_" ~
               "11110000_11111000_" ~
               "11111100_11111110_" ~
               "11111111_10101010");

        // Test right shift of more than one size_t's worth of bits
        b <<= 68;
        assert(toBitString(b) ==
               "00000000_00000000_" ~
               "00000000_00000000_" ~
               "00000000_00000000_" ~
               "00000000_00000000_" ~
               "00000000_00001000");

        b = BitArray(cast(const(bool)[])[
            1, 0, 0, 0, 0, 0, 0, 0,  1, 1, 0, 0, 0, 0, 0, 0,
            1, 1, 1, 0, 0, 0, 0, 0,  1, 1, 1, 1, 0, 0, 0, 0,
            1, 1, 1, 1, 1, 0, 0, 0,  1, 1, 1, 1, 1, 1, 0, 0,
            1, 1, 1, 1, 1, 1, 1, 0,  1, 1, 1, 1, 1, 1, 1, 1,
            1, 0, 1, 0, 1, 0, 1, 0,  0, 1, 0, 1, 0, 1, 0, 1,
        ]);
        b >>= 8;
        assert(toBitString(b) ==
               "11000000_11100000_" ~
               "11110000_11111000_" ~
               "11111100_11111110_" ~
               "11111111_10101010_" ~
               "01010101_00000000");

        // Test left shift of more than 1 size_t's worth of bits
        b >>= 68;
        assert(toBitString(b) ==
               "01010000_00000000_" ~
               "00000000_00000000_" ~
               "00000000_00000000_" ~
               "00000000_00000000_" ~
               "00000000_00000000");
    }
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.rollRight");

    static if (size_t.sizeof == 8)
    {
        size_t x = 0x12345678_90ABCDEF;
        size_t y = 0xFEDBCA09_87654321;

        assert(BitArray.rollRight(x, y, 32) == 0x90ABCDEF_FEDBCA09);
        assert(BitArray.rollRight(y, x, 4) == 0x11234567_890ABCDE);
    }
    else static if (size_t.sizeof == 4)
    {
        size_t x = 0x12345678;
        size_t y = 0x90ABCDEF;

        assert(BitArray.rollRight(x, y, 16) == 0x567890AB);
        assert(BitArray.rollRight(y, x, 4) == 0xF1234567);
    }
    else
        static assert(0, "Unsupported size_t");
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.rollLeft");

    static if (size_t.sizeof == 8)
    {
        size_t x = 0x12345678_90ABCDEF;
        size_t y = 0xFEDBCA09_87654321;

        assert(BitArray.rollLeft(x, y, 32) == 0x90ABCDEF_FEDBCA09);
        assert(BitArray.rollLeft(y, x, 4) == 0xEDBCA098_76543211);
    }
    else static if (size_t.sizeof == 4)
    {
        size_t x = 0x12345678;
        size_t y = 0x90ABCDEF;

        assert(BitArray.rollLeft(x, y, 16) == 0x567890AB);
        assert(BitArray.rollLeft(y, x, 4) == 0x0ABCDEF1);
    }
    else
        static assert(0, "Unsupported size_t");
}

nothrow @safe unittest
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.toString(sink)");

    auto b = BitArray(cast(const(bool)[])[0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1]);

    assert(toBitArray(b) == "[0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1]");

    assert(toBitString(b) == "00001111_00001111");
}

nothrow @safe unittest
{
    import pham.utl.object;
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.BitArray.get");

	auto b = BitArray(5, true);
    auto bytes = b.get!ubyte();
    assert(bytes.length == 1);
    assert(bytes.bytesToHexs() == "1F");

    b = BitArray(12);
	foreach (i; 0..12)
        b[i] = i < 10;
    bytes = b.get!ubyte();
    assert(bytes.length == 2);
    assert(bytes.bytesToHexs() == "FF03");
}

nothrow @safe unittest // bitLength
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.bitLength");

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

nothrow @safe unittest // trailingZeroBits
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.trailingZeroBits");

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

nothrow @safe unittest // highestBit
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.highestBit");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.lowestBit");

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

nothrow @safe unittest // getByteAt
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.getByteAt");

    assert(getByteAt(cast(ubyte)0x0, 0) == 0x0);
    assert(getByteAt(cast(ubyte)0x01, 0) == 0x01);
    assert(getByteAt(cast(ushort)0x23FF, 0) == 0xFF);
    assert(getByteAt(cast(ushort)0x23FF, 1) == 0x23);
    assert(getByteAt(cast(uint)0x23AB_1234, 2) == 0xAB);
    assert(getByteAt(cast(uint)0x23AB_1234, 3) == 0x23);
    assert(getByteAt(cast(ulong)0x23AB_1234_5678_1234, 6) == 0xAB);
    assert(getByteAt(cast(ulong)0x23AB_1234_5678_1234, 7) == 0x23);
}

nothrow @safe unittest // significantByteLength
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.significantByteLength");

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

unittest // numericBitCast
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.bit_array.numericBitCast");

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
