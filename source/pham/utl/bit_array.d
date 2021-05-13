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

import core.bitop : bsf, bt, btc, btr, bts, popcnt;
import std.algorithm.comparison : min;
import std.bitmanip : swapEndian;
import std.format : FormatSpec;
import std.range.primitives : isOutputRange, put;
import std.traits;

nothrow @safe:

pragma(inline, true)
T hostToNetworkOrder(T)(const T host) @nogc pure
if (isIntegral!T || isSomeChar!T)
{
    version (BigEndian)
        return host;
    else
        return swapEndian(host);
}

struct BitArray
{
nothrow @safe:

public:
    enum bitsPerByte = 8;
    enum bitsPerElement = size_t.sizeof * bitsPerByte;

    static size_t lengthToElement(size_t Bits)(size_t length) pure
    if (Bits == 8 || Bits == 16 || Bits == 32 || Bits == 64)
    {
        //return length > 0 ? (((length - 1) / Bits) + 1) : 0; // Safer for overflow
        static if (Bits == 64)
            return (length + 63) >> 6; // "x >> 6" is "x / 64"
        else static if (Bits == 32)
            return (length + 31) >> 5; // "x >> 5" is "x / 32"
        else static if (Bits == 16)
            return (length + 15) >> 4; // "x >> 4" is "x / 16"
        else
            return (length + 7) >> 3; // "x >> 3" is "x / 8"
    }

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
        this.values.length = lengthToElement!bitsPerElement(length);
        if (length)
            setAll(bit);
    }

    this(scope const(bool)[] bits) pure
    {
        const length = bits.length;
        this._length = length;
        this.values.length = lengthToElement!bitsPerElement(length);
        foreach (i, bit; bits)
        {
            if (bit)
                this.values[i / bitsPerElement] |= (cast(size_t)1 << (i % bitsPerElement));
        }
    }

    /*
     * Allocates space to hold the bit values in bytes. ubytes[0] represents
     * bits 0 - 7, ubytes[1] represents bits 8 - 15, etc. The LSB of each ubyte
     * represents the lowest index value; ubytes[0] & 1 represents bit 0,
     * ubytes[0] & 2 represents bit 1, ubytes[0] & 4 represents bit 2, etc.
     *
     */
    this(scope const(ubyte)[] bytes) pure
    {
        const length = bytes.length * bitsPerByte;
        this._length = length;
        this.values.length = lengthToElement!bitsPerElement(length);

        if (length)
        {
            size_t i, j;
            while (j + size_t.sizeof <= bytes.length)
            {
                static if (size_t.sizeof == 4)
                {
                    values[i++] = bytes[j]
                        | (cast(size_t)(bytes[j + 1]) << 8)
                        | (cast(size_t)(bytes[j + 2]) << 16)
                        | (cast(size_t)(bytes[j + 3]) << 24);
                }
                else
                {
                    values[i++] = bytes[j]
                        | (cast(size_t)(bytes[j + 1]) << 8)
                        | (cast(size_t)(bytes[j + 2]) << 16)
                        | (cast(size_t)(bytes[j + 3]) << 24)
                        | (cast(size_t)(bytes[j + 4]) << 32)
                        | (cast(size_t)(bytes[j + 5]) << 40)
                        | (cast(size_t)(bytes[j + 6]) << 48)
                        | (cast(size_t)(bytes[j + 7]) << 56);
                }

                j += size_t.sizeof;
            }

            // Remaining bytes
            switch (bytes.length - j)
            {
                static if (size_t.sizeof == 8)
                {
                case 7:
                    values[i] = (cast(size_t)(bytes[j + 2]) << 48);
                    goto case 6;
                case 6:
                    values[i] = (cast(size_t)(bytes[j + 2]) << 40);
                    goto case 5;
                case 5:
                    values[i] = (cast(size_t)(bytes[j + 2]) << 32);
                    goto case 4;
                case 4:
                    values[i] = (cast(size_t)(bytes[j + 2]) << 24);
                    goto case 3;
                }

                case 3:
                    values[i] = (cast(size_t)(bytes[j + 2]) << 16);
                    goto case 2;
                case 2:
                    values[i] |= (cast(size_t)(bytes[j + 1]) << 8);
                    goto case 1;
                case 1:
                    values[i] |= bytes[j];
                    break;
                default:
                    break;
            }
        }
    }

    this(scope const(size_t)[] values) pure
    {
        this._length = values.length * bitsPerElement;
        this.values = values.dup;
    }

    this(this) pure
    {
        this.values = values.dup;
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

    ref typeof(this) opOpAssign(string op)(const ref BitArray other) @nogc pure return
    if (op == "-" || op == "&" || op == "|" || op == "^")
    in
    {
        assert(other.length == length);
    }
    do
    {
        foreach (i, ref e; values)
        {
            static if (op == "-")
                e &= ~other.values[i];
            else
                mixin("e " ~ op ~ "= other.values[i];");
        }
        clearUnusedHighBits();

        return this;
    }

    ref typeof(this) opOpAssign(string op)(const ref BitArray other) pure return
    if (op == "~")
    {
        // TODO optimize using fullword assignment
        const oldLength = length;
        length = oldLength + other.length;
        foreach (i; 0..other.length)
            this[oldLength + i] = other[i];
        return this;
    }

    ref typeof(this) opOpAssign(string op)(bool bit) pure return
    if (op == "~")
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
            const dim = lengthToElement!bitsPerElement(length);
            const size_t wordsToShift = nBits / bitsPerElement;
            const size_t bitsToShift = nBits % bitsPerElement;

            if (wordsToShift < dim)
            {
                foreach_reverse (i; 1..dim - wordsToShift)
                    values[i + wordsToShift] = rollLeft(values[i], values[i - 1], bitsToShift);
                values[wordsToShift] = rollLeft(values[0], 0, bitsToShift);
            }

            foreach (i; 0..min(wordsToShift, dim))
                values[i] = 0;
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
            const dim = lengthToElement!bitsPerElement(length);
            const size_t wordsToShift = nBits / bitsPerElement;
            const size_t bitsToShift = nBits % bitsPerElement;

            if (wordsToShift + 1 < dim)
            {
                foreach (i; 0..dim - wordsToShift - 1)
                    values[i] = rollRight(values[i + wordsToShift + 1],
                                          values[i + wordsToShift],
                                          bitsToShift);
            }

            // The last word needs some care, as it must shift in 0's from past the
            // end of the array.
            if (wordsToShift < dim)
            {
                if (bitsToShift == 0)
                    values[dim - wordsToShift - 1] = values[dim - 1];
                else
                {
                    // Special case: if endBits == 0, then also endMask == 0.
                    const e = endBits;
                    const size_t lastWord = e
                        ? (values[fullWords] & endMask(e))
                        : values[fullWords - 1];
                    values[dim - wordsToShift - 1] = rollRight(0, lastWord, bitsToShift);
                }
            }

            foreach (i; 0..min(wordsToShift, dim))
                values[dim - i - 1] = 0;
        }

        return this;
    }

    /*
     * Support for binary bitwise operators for `BitArray`.
     */
    BitArray opBinary(string op)(const ref BitArray other) const pure
    if (op == "-" || op == "&" || op == "|" || op == "^")
    in
    {
        assert(other.length == length);
    }
    do
    {
        auto result = this.dup();
        return result.opOpAssign!op(other);
    }

    BitArray opBinary(string op)(const ref BitArray value) const pure
    if (op == "~")
    {
        auto result = this.dup();
        return result.opOpAssign!op(value);
    }

    BitArray opBinary(string op)(bool bit) const pure
    if (op == "~")
    {
        auto result = this.dup();
        result.length = length + 1;
        result[length] = bit;
        return result;
    }

    BitArray opBinaryRight(string op)(bool bit) const pure
    if (op == "~")
    {
        //TODO optimize fullword assignment
        BitArray result;
        result.length = length + 1;
        result[0] = bit;
        foreach (i; 0..length)
            result[1 + i] = this[i];
        return result;
    }

    /*
     * Supports comparison operators for `BitArray`.
     */
    int opCmp(const ref BitArray other) const @nogc pure @trusted
    {
        const lesser = length < other.length ? &this : &other;
        const f = lesser.fullWords;
        const e = lesser.endBits;

        foreach (i; 0..f)
        {
            if (values[i] != other.values[i])
                return values[i] & (size_t(1) << bsf(values[i] ^ other.values[i])) ? 1 : -1;
        }

        if (endBits)
        {
            const diff = values[f] ^ other.values[f];
            if (diff)
            {
                const i = bsf(diff);
                if (i < e)
                    return values[f] & (size_t(1) << i) ? 1 : -1;
            }
        }

        // Standard:
        // A bool value can be implicitly converted to any integral type,
        // with false becoming 0 and true becoming 1
        return (length > other.length) - (length < other.length);
    }

    /*
     * Support for operators == and != for `BitArray`.
     */
    bool opEquals(const ref BitArray other) const @nogc pure
    {
        if (length != other.length)
            return false;

        const f = fullWords;
        if (values[0..f] != other.values[0..f])
            return false;

        const e = endBits;
        if (!e)
            return true;

        const m = endMask(e);
        return (values[f] & m) == (other.values[f] & m);
    }

    bool opIndex(size_t index) const @nogc pure @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        return cast(bool)bt(values.ptr, index);
    }

    bool opIndexAssign(bool bit, size_t index) @nogc pure @trusted
    in
    {
        assert(index < length);
    }
    do
    {
        if (bit)
            bts(values.ptr, index);
        else
            btr(values.ptr, index);
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
      at index `start` and ends at index ($D end - 1)
      with the values specified by `bit`.
     */
    ref typeof(this) opSliceAssign(bool bit, size_t start, size_t end) @nogc return
    in
    {
        assert(start <= end, "start must be less or equal to end");
        assert(end <= length, "end must be less or equal to the length");
    }
    do
    {
        size_t startBlock = start / bitsPerElement;
        const size_t endBlock = end / bitsPerElement;
        const size_t startOffset = start % bitsPerElement;
        const size_t endOffset = end % bitsPerElement;

        if (startBlock == endBlock)
        {
            const size_t startBlockMask = ~((size_t(1) << startOffset) - 1);
            const size_t endBlockMask = (size_t(1) << endOffset) - 1;
            const size_t joinMask = startBlockMask & endBlockMask;
            if (bit)
                values[startBlock] |= joinMask;
            else
                values[startBlock] &= ~joinMask;
            return this;
        }

        if (startOffset != 0)
        {
            const size_t startBlockMask = ~((size_t(1) << startOffset) - 1);
            if (bit)
                values[startBlock] |= startBlockMask;
            else
                values[startBlock] &= ~startBlockMask;
            ++startBlock;
        }

        if (endOffset != 0)
        {
            const size_t endBlockMask = (size_t(1) << endOffset) - 1;
            if (bit)
                values[endBlock] |= endBlockMask;
            else
                values[endBlock] &= ~endBlockMask;
        }

        values[startBlock..endBlock] = size_t(0) - size_t(bit);

        return this;
    }

    /*
     * Support for unary operator ~ for `BitArray`.
     */
    BitArray opUnary(string op)() const pure
    if (op == "~")
    {
        auto result = BitArray(length);
        if (length)
        {
            foreach (i, e; values)
                result.values[i] = ~e;
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
                result += popcnt(values[i]);
            if (const e = endBits)
                result += popcnt(values[f] & endMask(e));
        }
        return result;
    }

    BitArray dup() const pure
    {
        auto result = BitArray(this.values);
        result._length = length; // Should be OK because we maintain this.values
        return result;
    }

    /*
     * Flips all the bits in the `BitArray`
     */
    void flip() @nogc pure
    {
        if (length)
        {
            foreach (ref e; values)
                e = ~e;
            clearUnusedHighBits();
        }
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
        auto result = cast(bool)bt(values.ptr, index);
        if (result)
            btr(values.ptr, index);
        else
            bts(values.ptr, index);
        return result;
    }

    T[] get(T)() const pure @trusted
    if (is(T == bool) || is(T == ubyte) || is(T == size_t))
    {
        static if (is(T == bool))
        {
            bool[] result = new bool[](length);
            foreach (i; 0..length)
                result[i] = cast(bool)bt(values.ptr, i);
            return result;
        }
        else static if (is(T == ubyte))
        {
            ubyte[] result = new ubyte[](lengthToElement!bitsPerByte(length));
            foreach (i; 0..result.length)
                // Shift to bring the required byte to LSB, then mask
                result[i] = cast(ubyte)((values[i / size_t.sizeof] >> ((i % size_t.sizeof) * 8)) & 0xff);
            return result;
        }
        else
            return values.dup;
    }

    void not() @nogc pure
    {
        flip();
    }

    /*
     * Reverses the bits of the `BitArray`.
     */
    void reverse() @nogc pure
    {
        if (length >= 2)
        {
            size_t lo = 0;
            size_t hi = length - 1;
            for (; lo < hi; lo++, hi--)
            {
                const bool t = this[lo];
                this[lo] = this[hi];
                this[hi] = t;
            }
        }
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
                result += (cast(ubyte*)values.ptr)[i];
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
        import std.array : Appender;

        auto f = FormatSpec!char("%s");
        Appender!string result;
        result.reserve(2 + (length * 2));
        return toString(result, f)[];
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
    ref W toString(W)(return ref W sink, scope const ref FormatSpec!char fmt) const
    if (isOutputRange!(W, char))
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
    @property size_t length() const @nogc pure
    {
        return _length;
    }

    /*
     * Sets the amount of bits in the `BitArray`.
     */
    @property size_t length(size_t newLength) pure
    {
        if (_length != newLength)
        {
            const oldSize = lengthToElement!bitsPerElement(length);
            const newSize = lengthToElement!bitsPerElement(newLength);
            if (oldSize != newSize)
            {
                values.length = newSize;
                // assumeSafeAppend does not support pure
                //() @trusted { values.assumeSafeAppend(); } ();
                if (newSize > oldSize)
                    values[oldSize..newSize] = 0;
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
            values[fullWords] &= endMask(e);
    }

    // Bit mask to extract the bits after the last full word
    pragma(inline, true);
    static size_t endMask(size_t endBits) @nogc pure
    {
        return (size_t(1) << endBits) - 1;
    }

    // Rolls double word (upper, lower) to the left by nBits and returns the
    // upper word of the result.
    static size_t rollLeft(size_t upper, size_t lower, size_t nBits) @nogc pure
    {
        return nBits == 0
            ? upper
            : (upper << nBits) | (lower >> (bitsPerElement - nBits));
    }

    // Rolls double word (upper, lower) to the right by nBits and returns the
    // lower word of the result.
    static size_t rollRight(size_t upper, size_t lower, size_t nBits) @nogc pure
    {
        return nBits == 0
            ? lower
            : (upper << (bitsPerElement - nBits)) | (lower >> nBits);
    }

    void setAll(bool value) @nogc pure
    {
        values[] = value ? ~size_t(0) : 0;
        if (value)
            clearUnusedHighBits();
    }

    ref W toBitArray(W)(return ref W sink) const
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

    ref W toBitString(W)(return ref W sink) const
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
    @property size_t endBits() const @nogc pure
    {
        return length % bitsPerElement;
    }

    // The result can cause out of bound if endBits returns 0
    @property size_t fullWords() const @nogc pure
    {
        return length / bitsPerElement;
    }

private:
    size_t[] values;
    size_t _length;
}


// Any below codes are private
private:


version (unittest)
{
    void checkBitArrayRange(ref BitArray b, size_t start, size_t end, bool v,
        size_t callerLine = __LINE__)
    {
        import pham.utl.utltest;

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

nothrow @safe unittest
{
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.length");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.opIndex");

    static void fun(const BitArray arr)
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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.opSliceAssign");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.flip");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.countBitSet");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.opApply");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.reverse");

    bool[5] data = [1,0,1,1,0];
    auto b = BitArray(data);
    b.reverse();
    foreach (i; 0..data.length)
        assert(b[i] == data[4 - i]);
}

nothrow @safe unittest
{
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.opEquals");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.opCmp");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.opUnary~");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.opBinary");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.opOpAssign");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.rollRight");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.rollLeft");

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
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.toString(sink)");

    auto b = BitArray(cast(const(bool)[])[0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1]);

    assert(toBitArray(b) == "[0,0,0,0,1,1,1,1,0,0,0,0,1,1,1,1]");

    assert(toBitString(b) == "00001111_00001111");
}

nothrow @safe unittest
{
    import pham.utl.utlobject;
    import pham.utl.utltest;
    traceUnitTest("unittest utl.bit_array.BitArray.get");

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
