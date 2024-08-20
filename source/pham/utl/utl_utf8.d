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

module pham.utl.utl_utf8;

import std.algorithm.mutation : swapAt;
import std.range.primitives : empty, front, popFront, put, save;
import std.string : representation;
import std.traits : isSomeChar;

nothrow @safe:

struct UTF8Iterator
{
    char[encodeUTF8MaxLength] codeBuffer = 0;
    dchar code = 0;
    ubyte count;
}

/**
 * Encodes dchar `c` into the static char array, `buffer`, and returns a slice
 * of the encoded characters. When `c` is invalid, it will return empty slice
 */
enum encodeUTF8MaxLength = 4;
char[] encodeUTF8(return ref char[encodeUTF8MaxLength] buffer, const(dchar) c) @nogc pure
{
    if (c <= 0x7F)
    {
        buffer[0] = cast(char)c;
        return buffer[0..1];
    }
    else if (c <= 0x7FF)
    {
        buffer[0] = cast(char)(0xC0 | (c >> 6));
        buffer[1] = cast(char)(0x80 | (c & 0x3F));
        return buffer[0..2];
    }
    else if (c <= 0xFFFF)
    {
        if (0xD800 <= c && c <= 0xDFFF)
            return null;

        buffer[0] = cast(char)(0xE0 | (c >> 12));
        buffer[1] = cast(char)(0x80 | ((c >> 6) & 0x3F));
        buffer[2] = cast(char)(0x80 | (c & 0x3F));
        return buffer[0..3];
    }
    else if (c <= 0x10FFFF)
    {
        buffer[0] = cast(char)(0xF0 | (c >> 18));
        buffer[1] = cast(char)(0x80 | ((c >> 12) & 0x3F));
        buffer[2] = cast(char)(0x80 | ((c >> 6) & 0x3F));
        buffer[3] = cast(char)(0x80 | (c & 0x3F));
        return buffer[0..4];
    }
    else
        return null;
}

struct UTF16Iterator
{
    wchar[encodeUTF16MaxLength] codeBuffer = 0;
    dchar code = 0;
    ubyte count;
}

/**
 * Encodes dchar `c` into the static wchar array, `buffer`, and returns a slice
 * of the encoded characters. When `c` is invalid, it will return empty slice
 */
enum encodeUTF16MaxLength = 2;
wchar[] encodeUTF16(return ref wchar[encodeUTF16MaxLength] buffer, const(dchar) c) @nogc pure
{
    if (c <= 0xFFFF)
    {
        if (0xD800 <= c && c <= 0xDFFF)
            return null;

        buffer[0] = cast(wchar)c;
        return buffer[0..1];
    }
    
    if (c <= 0x10FFFF)
    {
        buffer[0] = cast(wchar)((((c - 0x10000) >> 10) & 0x3FF) + 0xD800);
        buffer[1] = cast(wchar)(((c - 0x10000) & 0x3FF) + 0xDC00);
        return buffer[0..2];
    }

    return null;
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

version(none)
pragma(inline, true)
bool isUTF16SurrogateHigh(const(wchar) c) @nogc pure
{
    enum unicodeSurrogateHighBegin = 0xD800;
    enum unicodeSurrogateHighEnd = 0xDBFF;
    return c >= unicodeSurrogateHighBegin && c <= unicodeSurrogateHighEnd;
}

version(none)
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
