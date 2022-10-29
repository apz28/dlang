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

module pham.utl.utf8;

import std.algorithm.mutation : swapAt;
import std.range.primitives : empty, front, popFront, put, save;
import std.string : representation;
import std.traits : isIntegral, isSomeChar;

nothrow @safe:

void inplaceMoveToLeft(ref ubyte[] data, size_t fromIndex, size_t toIndex, size_t nBytes) pure
in
{
    assert(nBytes > 0);
    assert(toIndex < fromIndex);
    assert(toIndex + nBytes <= data.length);
    assert(fromIndex + nBytes <= data.length);
}
do
{
    import core.stdc.string : memmove;

    (() @trusted => memmove(data.ptr + toIndex, data.ptr + fromIndex, nBytes))();
}

bool nextUTF8Char(scope const(ubyte)[] str, size_t pos, out dchar cCode, out ubyte cCount) @nogc pure
{
    if (pos >= str.length)
    {
        cCount = 0;
        cCode = 0;
        return false;
    }

    ubyte c = str[pos++];

    /* The following encodings are valid utf8 combinations:
     *  0xxxxxxx
     *  110xxxxx 10xxxxxx
     *  1110xxxx 10xxxxxx 10xxxxxx
     *  11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
     *  111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
     *  1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
     */
    if (c & 0x80)
    {
        const extraBytesToRead = unicodeTrailingBytesForUTF8[c];
        cCount = cast(ubyte)(extraBytesToRead + 1);

        if (cCount + pos - 1 > str.length)
        {
            // Return max count to avoid buffer overrun?
            //while (cCount + pos - 1 > str.length)
            //    cCount--;

            cCode = 0;
            return false;
        }

        uint res = 0;

        switch (extraBytesToRead)
        {
            case 5:
                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 4;

            case 4:
                if (extraBytesToRead != 4 && (c & 0xC0) != 0x80)
                {
                    cCode = 0;
                    return false;
                }

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 3;

            case 3:
                if (extraBytesToRead != 3 && (c & 0xC0) != 0x80)
                {
                    cCode = 0;
                    return false;
                }

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 2;

            case 2:
                if (extraBytesToRead != 2 && (c & 0xC0) != 0x80)
                {
                    cCode = 0;
                    return false;
                }

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 1;

            case 1:
                if (extraBytesToRead != 1 && (c & 0xC0) != 0x80)
                {
                    cCode = 0;
                    return false;
                }

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 0;

            case 0:
                if (extraBytesToRead != 0 && (c & 0xC0) != 0x80)
                {
                    cCode = 0;
                    return false;
                }

                res += c;
                break;

            default:
                assert(0);
        }

        cCode = res - unicodeOffsetsFromUTF8[extraBytesToRead];
        return true;
    }
    else
    {
        cCount = 1;
        cCode = c;
        return true;
    }
}

pragma(inline, true)
bool nextUTF8Char(scope const(char)[] str, size_t pos, out dchar cCode, out ubyte cCount) @nogc pure
{
    return nextUTF8Char(str.representation, pos, cCode, cCount);
}

version (none)
pragma(inline, true)
bool isUTF16SurrogateHigh(const(wchar) c) @nogc pure
{
    enum unicodeSurrogateHighBegin = 0xD800;
    enum unicodeSurrogateHighEnd = 0xDBFF;
    return c >= unicodeSurrogateHighBegin && c <= unicodeSurrogateHighEnd;
}

version (none)
pragma(inline, true)
bool isUTF16SurrogateLow(const(wchar) c) @nogc pure
{
    enum unicodeSurrogateLowBegin = 0xDC00;
    enum unicodeSurrogateLowEnd = 0xDFFF;
    return c >= unicodeSurrogateLowBegin && c <= unicodeSurrogateLowEnd;
}

bool nextUTF16Char(scope const(ushort)[] str, size_t pos, out dchar cCode, out ubyte cCount) @nogc pure
{
    if (pos >= str.length)
    {
        cCount = 0;
        cCode = 0;
        return false;
    }

    const ushort c1 = str[pos++];

    // normal
	if (c1 < unicodeSurr1UTF16 && unicodeSurr3UTF16 <= c1)
    {
        cCount = 1;
        cCode = c1;
        return true;
    }
    // surrogate sequence
	else if (unicodeSurr1UTF16 <= c1 && c1 < unicodeSurr2UTF16 && pos < str.length)
    {
        const ushort c2 = str[pos];
        if (unicodeSurr2UTF16 <= c2 && c2 < unicodeSurr3UTF16)
        {
            cCount = 2;
            cCode = ((c1 - unicodeSurr1UTF16) << 10 | (c2 - unicodeSurr2UTF16)) + unicodeSurrSelfUTF16;
            return true;
        }
        else
        {
            cCount = 1;
            cCode = 0;
            return false;
        }
    }
    else
    {
        cCount = 1;
        cCode = 0;
        return false;
    }
}

pragma(inline, true)
bool nextUTF16Char(scope const(wchar)[] str, size_t pos, out dchar cCode, out ubyte cCount) @nogc pure
{
    return nextUTF16Char(str.representation, pos, cCode, cCount);
}

struct NoDecodeInputRange(alias s, V)
if (isSomeChar!V || is(V == ubyte))
{
@nogc nothrow pure @safe:

public:
    V opIndex(size_t i) const
    in
    {
        assert(i < s.length);
    }
    do
    {
        return s[i];
    }

    pragma(inline, true)
    void popFront()
    {
        p++;
    }

    pragma(inline, true)
    @property bool empty() const
    {
        return p >= s.length;
    }

    pragma(inline, true)
    @property V front() const
    {
        return s[p];
    }

    @property size_t length() const
    {
        return s.length;
    }

    @property size_t offset() const
    {
        return p;
    }

private:
    size_t p;
}

struct NoDecodeOutputRange(alias s, V)
if (isSomeChar!V || is(V == ubyte))
{
@nogc nothrow pure @safe:

public:
    V opIndexAssign(V v, size_t i)
    in
    {
        assert(i < s.length);
    }
    do
    {
        s[i] = v;
        return v;
    }

    pragma(inline, true)
    void put(V v)
    {
        s[p++] = v;
    }

    @property size_t length() const
    {
        return s.length;
    }

    @property size_t offset() const
    {
        return p;
    }

private:
    size_t p;
}

struct UTF8CharRange
{
@nogc nothrow @safe:

public:
    dchar replacementChar = dchar.max;

public:
    this(scope return const(char)[] source) pure
    {
        this._source = source;
        this.reset();
    }

    void popFront() pure scope
    in
    {
        assert(!empty);
    }
    do
    {
        _previousChar = _currentChar;
        _previousP = _p;

        if (_p >= _source.length)
        {
            _empty = true;
            _dcount = 0;
            _currentChar = 0;
            return;
        }

        if (!nextUTF8Char(_source, _p, _currentChar, _dcount))
            _currentChar = replacementChar;
        _p += _dcount;
    }

    void reset() pure scope
    {
        _currentChar = _previousChar = 0;
        _p = _previousP = 0;
        _dcount = 0;
        _empty = _source.length == 0;
        if (!_empty)
            popFront();
    }

    pragma(inline, true)
    @property ubyte dcount() const pure scope
    {
        return _dcount;
    }

    pragma(inline, true)
    @property bool empty() const pure scope
    {
        return _empty;
    }

    pragma(inline, true)
    @property dchar front() const pure scope
    {
        return _currentChar;
    }

    pragma(inline, true)
    @property bool isLast() const pure scope
    {
        return _p >= _source.length && !_empty;
    }

    pragma(inline, true)
    @property size_t length() const pure scope
    {
        return _source.length - _previousP;
    }

    pragma(inline, true)
    @property size_t position() const pure scope
    {
        return _p;
    }

    pragma(inline, true)
    @property dchar previousChar() const pure scope
    {
        return _previousChar;
    }

    pragma(inline, true)
    @property size_t previousPosition() const pure scope
    {
        return _previousP;
    }

private:
    const(char)[] _source;
    size_t _p, _previousP;
    dchar _currentChar = 0, _previousChar = 0;
    ubyte _dcount;
    bool _empty;
}
struct ShortStringBufferSize(T, ushort ShortSize)
if (ShortSize > 0 && (isSomeChar!T || isIntegral!T))
{
@safe:

public:
    this(this) nothrow pure
    {
        _longData = _longData.dup;
    }

    this(bool setShortLength) nothrow pure
    {
        if (setShortLength)
            this._length = ShortSize;
    }

    this(ushort shortLength) nothrow pure
    {
        if (shortLength)
        {
            this._length = shortLength;
            if (shortLength > ShortSize)
                this._longData.length = shortLength;
        }
    }

    this(scope const(T)[] values) nothrow pure
    {
        setData(values);
    }

    ref typeof(this) opAssign(scope const(T)[] values) nothrow return
    {
        setData(values);
        return this;
    }

    ref typeof(this) opOpAssign(string op)(T c) nothrow pure return
    if (op == "~" || op == "+")
    {
        return put(c);
    }

    ref typeof(this) opOpAssign(string op)(scope const(T)[] s) nothrow pure return
    if (op == "~" || op == "+")
    {
        return put(s);
    }

    static if (isIntegral!T)
    ref typeof(this) opOpAssign(string op)(scope const(T)[] rhs) @nogc nothrow pure
    if (op == "&" || op == "|" || op == "^")
    {
        const len = _length > rhs.length ? rhs.length : _length;
        if (useShortSize)
        {
            foreach (i; 0..len)
                mixin("_shortData[i] " ~ op ~ "= rhs[i];");

            static if (op == "&")
            if (len < _length)
                _shortData[len.._length] = 0;
        }
        else
        {
            foreach (i; 0..len)
                mixin("_longData[i] " ~ op ~ "= rhs[i];");

            static if (op == "&")
            if (len < _length)
                _longData[len.._length] = 0;
        }
        return this;
    }

    size_t opDollar() const @nogc nothrow pure
    {
        return _length;
    }

    bool opEquals(scope const(typeof(this)) rhs) const @nogc nothrow pure
    {
        scope const rhsd = rhs.useShortSize ? rhs._shortData[0..rhs._length] : rhs._longData[0..rhs._length];
        return useShortSize ? (_shortData[0.._length] == rhsd) : (_longData[0.._length] == rhsd);
    }

    bool opEquals(scope const(T)[] rhs) const @nogc nothrow pure
    {
        return useShortSize ? (_shortData[0.._length] == rhs) : (_longData[0.._length] == rhs);
    }

    inout(T)[] opIndex() inout nothrow pure return
    {
        return useShortSize ? _shortData[0.._length] : _longData[0.._length];
    }

    T opIndex(const(size_t) index) const @nogc nothrow pure
    in
    {
        assert(index < length);
    }
    do
    {
        return useShortSize ? _shortData[index] : _longData[index];
    }

    inout(T)[] opSlice(const(size_t) beginIndex, const(size_t) endIndex) inout nothrow pure return
    in
    {
        assert(beginIndex <= endIndex);
    }
    do
    {
        if (beginIndex >= _length)
            return [];
        else
            return endIndex > _length
                ? (useShortSize ? _shortData[beginIndex.._length] : _longData[beginIndex.._length])
                : (useShortSize ? _shortData[beginIndex..endIndex] : _longData[beginIndex..endIndex]);
    }

    ref typeof(this) opIndexAssign(T c, const(size_t) index) @nogc nothrow return
    in
    {
        assert(index < length);
    }
    do
    {
        if (useShortSize)
            _shortData[index] = c;
        else
            _longData[index] = c;
        return this;
    }

    static if (isIntegral!T)
    ref typeof(this) opIndexOpAssign(string op)(T c, const(size_t) index) @nogc nothrow pure
    if (op == "&" || op == "|" || op == "^")
    in
    {
        assert(index < length);
    }
    do
    {
        if (useShortSize)
            mixin("_shortData[index] " ~ op ~ "= c;");
        else
            mixin("_longData[index] " ~ op ~ "= c;");
        return this;
    }

    ref typeof(this) chopFront(const(size_t) chopLength) nothrow pure return
    {
        if (chopLength >= _length)
            return clear();

        const newLength = _length - chopLength;
        if (useShortSize)
            _shortData[0..newLength] = _shortData[chopLength.._length];
        else
        {
            // Switch from long to short?
            if (useShortSize(newLength))
                _shortData[0..newLength] = _longData[chopLength.._length];
            else
                _longData[0..newLength] = _longData[chopLength.._length];
        }
        _length = newLength;
        return this;
    }

    ref typeof(this) chopTail(const(size_t) chopLength) nothrow pure return
    {
        if (chopLength >= _length)
            return clear();

        const newLength = _length - chopLength;
        // Switch from long to short?
        if (!useShortSize && useShortSize(newLength))
            _shortData[0..newLength] = _longData[chopLength.._length];
        _length = newLength;
        return this;
    }

    ref typeof(this) clear(bool setShortLength = false, bool disposing = false) nothrow pure return
    {
        if (setShortLength || disposing)
        {
            _shortData[] = 0;
            _longData[] = 0;
        }
        _length = setShortLength ? ShortSize : 0;
        return this;
    }

    T[] consume() nothrow pure
    {
        T[] result = _length != 0
            ? (useShortSize ? _shortData[0.._length].dup : _longData[0.._length])
            : [];

        _shortData[] = 0;
        _longData = null;
        _length = 0;

        return result;
    }

    immutable(T)[] consumeUnique() nothrow pure @trusted
    {
        T[] result = _length != 0
            ? (useShortSize ? _shortData[0.._length].dup : _longData[0.._length])
            : [];

        _shortData[] = 0;
        _longData = null;
        _length = 0;

        return cast(immutable(T)[])(result);
    }

    void dispose(bool disposing) nothrow pure
    {
        _shortData[] = 0;
        _longData[] = 0;
        _longData = null;
        _length = 0;
    }

    inout(T)[] left(size_t len) inout nothrow pure return
    {
        if (len >= _length)
            return opIndex();
        else
            return opIndex()[0..len];
    }

    ref typeof(this) put(T c) nothrow pure return
    {
         const newLength = _length + 1;
        // Still in short?
        if (useShortSize(newLength))
            _shortData[_length++] = c;
        else
        {
            if (useShortSize)
                switchToLongData(1);
            else if (_longData.length < newLength)
                _longData.length = alignAddtionalLength(newLength);
            _longData[_length++] = c;
        }
        return this;
    }

    ref typeof(this) put(scope const(T)[] s) nothrow pure return
    {
        if (!s.length)
            return this;

        const newLength = _length + s.length;
        // Still in short?
        if (useShortSize(newLength))
        {
            _shortData[_length..newLength] = s[0..$];
        }
        else
        {
            if (useShortSize)
                switchToLongData(s.length);
            else if (_longData.length < newLength)
                _longData.length = alignAddtionalLength(newLength);
            _longData[_length..newLength] = s[0..$];
        }
        _length = newLength;
        return this;
    }

    static if (is(T == char))
    ref typeof(this) put(dchar c) nothrow pure return
    {
        import std.typecons : Yes;
        import std.utf : encode, UseReplacementDchar;

        char[4] buffer;
        const len = encode!(Yes.useReplacementDchar)(buffer, c);
        return put(buffer[0..len]);
    }

    ref typeof(this) reverse() @nogc nothrow pure
    {
        if (const len = length)
        {
            const last = len - 1;
            const steps = len / 2;
            if (useShortSize)
            {
                for (size_t i = 0; i < steps; i++)
                    _shortData.swapAt(i, last - i);
            }
            else
            {
                for (size_t i = 0; i < steps; i++)
                    _longData.swapAt(i, last - i);
            }
        }
        return this;
    }

    inout(T)[] right(size_t len) inout nothrow pure return
    {
        if (len >= _length)
            return opIndex();
        else
            return opIndex()[_length - len.._length];
    }

    static if (isSomeChar!T)
    immutable(T)[] toString() const nothrow pure
    {
        return _length != 0
            ? (useShortSize ? _shortData[0.._length].idup : _longData[0.._length].idup)
            : [];
    }

    static if (isSomeChar!T)
    ref Writer toString(Writer)(return ref Writer sink) const pure
    {
        if (_length)
            put(sink, opIndex());
        return sink;
    }

    pragma (inline, true)
    @property bool empty() const @nogc nothrow pure
    {
        return _length == 0;
    }

    pragma(inline, true)
    @property size_t length() const @nogc nothrow pure
    {
        return _length;
    }

    pragma(inline, true)
    @property static size_t shortSize() @nogc nothrow pure
    {
        return ShortSize;
    }

    pragma (inline, true)
    @property bool useShortSize() const @nogc nothrow pure
    {
        return _length <= ShortSize;
    }

    pragma(inline, true)
    @property bool useShortSize(const(size_t) checkLength) const @nogc nothrow pure
    {
        return checkLength <= ShortSize;
    }

private:
    pragma(inline, true)
    size_t alignAddtionalLength(const(size_t) additionalLength) @nogc nothrow pure
    {
        if (additionalLength <= overReservedLength)
            return overReservedLength;
        else
            return ((additionalLength + overReservedLength - 1) / overReservedLength) * overReservedLength;
    }

    void setData(scope const(T)[] values) nothrow pure
    {
        _length = values.length;
        if (_length)
        {
            if (useShortSize)
            {
                _shortData[0.._length] = values[0.._length];
            }
            else
            {
                if (_longData.length < _length)
                    _longData.length = _length;
                _longData[0.._length] = values[0.._length];
            }
        }
    }

    void switchToLongData(const(size_t) additionalLength) nothrow pure
    {
        const capacity = alignAddtionalLength(_length + additionalLength);
        if (_longData.length < capacity)
            _longData.length = capacity;
        if (_length)
            _longData[0.._length] = _shortData[0.._length];
    }

private:
    enum overReservedLength = 1_000u;
    size_t _length;
    T[] _longData;
    T[ShortSize] _shortData = 0;
}

template ShortStringBuffer(T)
if (isSomeChar!T || isIntegral!T)
{
    private enum overheadSize = ShortStringBufferSize!(T, 1u).sizeof;
    alias ShortStringBuffer = ShortStringBufferSize!(T, 256u - overheadSize);
}


// Any below codes are private
private:

// 0xd800-0xdc00 encodes the high 10 bits of a pair.
// 0xdc00-0xe000 encodes the low 10 bits of a pair.
// the value is those 20 bits plus 0x10000.
enum unicodeSurr1UTF16 = 0xD800;
enum unicodeSurr2UTF16 = 0xDC00;
enum unicodeSurr3UTF16 = 0xE000;
enum unicodeSurrSelfUTF16 = 0x1_0000;

static immutable uint[] unicodeOffsetsFromUTF8 = [
    0x0000_0000, 0x0000_3080, 0x000E_2080, 0x03C8_2080, 0xFA08_2080, 0x8208_2080,
    ];

static immutable ubyte[] unicodeTrailingBytesForUTF8 = [
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5,
    ];

nothrow @safe unittest // inplaceMoveToLeft
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.inplaceMoveToLeft");

    auto chars = cast(ubyte[])"1234567890".dup;
    inplaceMoveToLeft(chars, 5, 0, 5);
    assert(chars == "6789067890");
}

@safe unittest // ShortStringBufferSize
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.ShortStringBufferSize");

    alias TestBuffer = ShortStringBufferSize!(char, 5);

    TestBuffer s;
    assert(s.length == 0);
    s.put('1');
    assert(s.length == 1);
    s.put("234");
    assert(s.length == 4);
    assert(s.toString() == "1234");
    assert(s[] == "1234");
    s.clear();
    assert(s.length == 0);
    s.put("abc");
    assert(s.length == 3);
    assert(s.toString() == "abc");
    assert(s[] == "abc");
    assert(s.left(1) == "a");
    assert(s.left(10) == "abc");
    assert(s.right(2) == "bc");
    assert(s.right(10) == "abc");
    s.put("defghijklmnopqrstuvxywz");
    assert(s.length == 26);
    assert(s.toString() == "abcdefghijklmnopqrstuvxywz");
    assert(s[] == "abcdefghijklmnopqrstuvxywz");
    assert(s.left(5) == "abcde");
    assert(s.left(20) == "abcdefghijklmnopqrst");
    assert(s.right(5) == "vxywz");
    assert(s.right(20) == "ghijklmnopqrstuvxywz");

    TestBuffer s2;
    s2 ~= s[];
    assert(s2.length == 26);
    assert(s2.toString() == "abcdefghijklmnopqrstuvxywz");
    assert(s2[] == "abcdefghijklmnopqrstuvxywz");
}

nothrow @safe unittest // ShortStringBufferSize.reverse
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.ShortStringBufferSize.reverse");

    ShortStringBufferSize!(int, 3) a;

    a.clear().put([1, 2]);
    assert(a.reverse()[] == [2, 1]);

    a.clear().put([1, 2, 3, 4, 5]);
    assert(a.reverse()[] == [5, 4, 3, 2, 1]);
}
