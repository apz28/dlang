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
import std.range.primitives : ElementType, empty, front, isInfinite, isInputRange, popFront, put, save;
import std.traits : isIntegral, isNarrowString, isSomeChar, Unqual;

nothrow @safe:

enum unicodeHalfShift = 10;
enum unicodeHalfBase = 0x0001_0000;
enum unicodeHalfMask = 0x03FF;
enum unicodeSurrogateHighBegin = 0xD800;
enum unicodeSurrogateHighEnd = 0xDBFF;
enum unicodeSurrogateLowBegin = 0xDC00;
enum unicodeSurrogateLowEnd = 0xDFFF;

immutable ubyte[] unicodeTrailingBytesForUTF8 = [
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1, 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
    2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2, 3,3,3,3,3,3,3,3,4,4,4,4,5,5,5,5
];

immutable uint[] unicodeOffsetsFromUTF8 = [
    0x00000000, 0x00003080, 0x000E2080, 0x03C82080, 0xFA082080, 0x82082080
];

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

dchar utf8NextChar(const(char)[] str, ref size_t pos, out size_t cnt)
{
    cnt = 0;
    if (pos >= str.length)
        return 0;

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

        if (extraBytesToRead + pos > str.length)
            return dchar.max;

        dchar res = 0;

        switch (extraBytesToRead)
        {
            case 5:
                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 4;
            case 4:
                if (extraBytesToRead != 4 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 3;
            case 3:
                if (extraBytesToRead != 3 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 2;
            case 2:
                if (extraBytesToRead != 2 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 1;
            case 1:
                if (extraBytesToRead != 1 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                res <<= 6;
                c = str[pos++];
                goto case 0;
            case 0:
                if (extraBytesToRead != 0 && (c & 0xC0) != 0x80)
                    return dchar.max;

                res += c;
                break;
            default:
                assert(0);
        }

        cnt = extraBytesToRead + 1;
        return res - unicodeOffsetsFromUTF8[extraBytesToRead];
    }
    else
    {
        cnt = 1;
        return c;
    }
}

enum NumericLexerFlag : byte
{
    none = 0,
    allowFloat = 1,
    allowHex = 2,
    all = allowFloat | allowHex
}

enum bool isNumericLexerRange(Range) = isInputRange!Range && isSomeChar!(ElementType!Range) && !isInfinite!Range;

struct NumericLexer(Range)
if (isNumericLexerRange!Range)
{
nothrow @safe:

public:
    alias RangeElement = Unqual!(ElementType!Range);

public:
    this(Range range, NumericLexerFlag allowFlag) pure
    {
        this._value = range;
        this._allowFlag = allowFlag;
        this._hasDecimalChar = this._neg = this._hex = false;
        checkHasDigits();
    }

    pragma(inline, true)
    bool allowDecimalChar(const(RangeElement) c) const @nogc pure
    {
        return c == decimalChar && !_hasDecimalChar && (allowFlag & NumericLexerFlag.allowFloat);
    }

    pragma(inline, true)
    bool isDigitChar(const(RangeElement) c) const @nogc pure
    {
        return c >= '0' && c <= '9';
    }

    pragma(inline, true)
    bool isHexChar(const(RangeElement) c) const @nogc pure
    {
        return (c >= '0' && c <= '9') ||
                (c >= 'A' && c <= 'F') ||
                (c >= 'a' && c <= 'f');
    }

    pragma(inline, true)
    bool isSpaceChar(const(RangeElement) c) const @nogc pure
    {
        return c == ' ' ||
                c == '\r' ||
                c == '\n' ||
                c == '\f' ||
                c == '\t' ||
                c == '\v' ||
                c == '_' ||
                c == groupSeparator;
    }

    void popDecimalChar() pure
    in
    {
        assert(!empty);
        assert(front == decimalChar);
    }
    do
    {
        _hasDecimalChar = true;
        popFront();
    }

    void popFront() pure
    {
        scope (failure) assert(0);

        if (_hasSavedFront)
            _hasSavedFront = false;
        else
            _value.popFront();
        while (!_value.empty && (_value.front == '_' || _value.front == groupSeparator))
            _value.popFront();
    }

    void skipSpaces() pure
    {
        while (!empty && isSpaceChar(front))
            popFront();
    }

    RangeElement toUpper(const(RangeElement) c) const @nogc pure
    {
        return (c >= 'a' && c <= 'z')
            ? cast(RangeElement)(c - ('a' - 'A'))
            : c;
    }

    @property NumericLexerFlag allowFlag() const @nogc pure
    {
        return _allowFlag;
    }

    @property bool empty() const @nogc pure
    {
        return _value.empty && !_hasSavedFront;
    }

    @property RangeElement front() const pure
    {
        scope (failure) assert(0);

        return _hasSavedFront ? _savedFront : _value.front;
    }

    @property bool hasDigits() const @nogc pure
    {
        return _hasDigits;
    }

    @property bool hex() const @nogc pure
    {
        return _hex;
    }

    @property bool neg() const @nogc pure
    {
        return _neg;
    }

public:
    RangeElement decimalChar = '.';
    RangeElement groupSeparator = ',';

private:
    void checkHasDigits() pure
    {
        scope (failure) assert(0);

        _hasDigits = false;
        _hasSavedFront = false;

        skipSpacesImpl();
        if (_value.empty)
            return;

        const c = _value.front;
        if (c == '-')
        {
            _neg = true;
            _value.popFront();
        }
        else if (c == '+')
            _value.popFront();
        else if (c == '0' && (allowFlag & NumericLexerFlag.allowHex))
        {
            _savedFront = c;
            _hasSavedFront = true;
            _hasDigits = true;
            _value.popFront();
            if (_value.empty)
                return;

            const x = _value.front;
            if (x == 'x' || x == 'X')
            {
                _hex = true;
                _hasSavedFront = false;
                _hasDigits = false;
                popFrontImpl();
            }
        }

        if (_value.empty)
            return;

        const c2 = _value.front;
        _hasDigits = hex ? isHexChar(c2) : (isDigitChar(c2) | allowDecimalChar(c2));
    }

    void popFrontImpl() pure
    {
        scope (failure) assert(0);

        _value.popFront();
        while (!_value.empty && (_value.front == '_' || _value.front == groupSeparator))
            _value.popFront();
    }

    void skipSpacesImpl() pure
    {
        scope (failure) assert(0);

        while (!_value.empty && isSpaceChar(_value.front))
            popFrontImpl();
    }

private:
    Range _value;
    NumericLexerFlag _allowFlag;
    RangeElement _savedFront;
    bool _hasDigits, _hasSavedFront, _hex, _neg, _hasDecimalChar;
}

struct ShortStringBufferSize(Char, ushort Size)
if (Size > 0 && (isSomeChar!Char || isIntegral!Char))
{
@safe:

public:
    this(this) nothrow pure
    {
        _longData = _longData.dup;
    }

    this(bool setSize)
    {
        if (setSize)
            this._length = Size;
    }

    ref typeof(this) opAssign(scope const(Char)[] values) nothrow return
    {
        clear();
        _length = values.length;
        if (_length)
        {
            if (_length <= Size)
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
        return this;
    }

    alias opOpAssign(string op : "~") = put;

    size_t opDollar() const @nogc nothrow pure
    {
        return _length;
    }

    Char opIndex(size_t i) const @nogc nothrow pure
    in
    {
        assert(i < length);
    }
    do
    {
        return _length <= Size ? _shortData[i] : _longData[i];
    }

    ref typeof(this) opIndexAssign(Char c, size_t i) return
    in
    {
        assert(i < length);
    }
    do
    {
        if (_length <= Size)
            _shortData[i] = c;
        else
            _longData[i] = c;
        return this;
    }

    Char[] opSlice() nothrow pure return
    {
        return _length <= Size ? _shortData[0.._length] : _longData[0.._length];
    }

    ref typeof(this) clear(bool setSize = false)() nothrow pure
    {
        _length = 0;
        static if (setSize)
        {
            _shortData[] = 0;
            _longData[] = 0;
            _length = Size;
        }
        return this;
    }

    Char[] left(size_t len) nothrow pure return
    {
        if (len >= _length)
            return opSlice();
        else
            return opSlice()[0..len];
    }

    ref typeof(this) put(Char c) nothrow pure return
    {
        if (_length < Size)
            _shortData[_length++] = c;
        else
        {
            if (_length == Size)
                switchToLongData(1);
            else if (_longData.length <= _length)
                _longData.length = _length + overReservedLength;
            _longData[_length++] = c;
        }
        return this;
    }

    ref typeof(this) put(scope const(Char)[] s) nothrow pure return
    {
        if (!s.length)
            return this;

        const newLength = _length + s.length;

        enum bugChecklimit = 1024 * 1024 * 4; // 4MB
        assert(newLength <= bugChecklimit);

        if (newLength <= Size)
        {
            _shortData[_length..newLength] = s[0..$];
        }
        else
        {
            if (_length && _length <= Size)
                switchToLongData(s.length);
            else if (_longData.length < newLength)
                _longData.length = newLength + overReservedLength;
            _longData[_length..newLength] = s[0..$];
        }
        _length = newLength;
        return this;
    }

    ref typeof(this) reverse() @nogc nothrow pure
    {
        if (const len = length)
        {
            const last = len - 1;
            const steps = len / 2;
            if (_length <= Size)
            {
                for (size_t i = 0; i < steps; i++)
                {
                    _shortData.swapAt(i, last - i);
                }
            }
            else
            {
                for (size_t i = 0; i < steps; i++)
                {
                    _longData.swapAt(i, last - i);
                }
            }
        }
        return this;
    }

    Char[] right(size_t len) nothrow pure return
    {
        if (len >= _length)
            return opSlice();
        else
            return opSlice()[_length - len.._length];
    }

    static if (isSomeChar!Char)
    immutable(Char)[] toString() const nothrow pure
    {
        return _length != 0
            ? (_length <= Size ? _shortData[0.._length].idup : _longData[0.._length].idup)
            : null;
    }

    static if (isSomeChar!Char)
    ref Writer toString(Writer)(return ref Writer sink) const pure
    {
        if (_length)
            put(sink, opSlice());
        return sink;
    }

    @property bool empty() const @nogc nothrow pure
    {
        return _length == 0;
    }

    @property size_t length() const @nogc nothrow pure
    {
        return _length;
    }

    pragma(inline, true)
    @property static size_t shortSize() @nogc nothrow pure
    {
        return Size;
    }

private:
    void switchToLongData(const(size_t) addtionalLength) nothrow pure
    {
        const capacity = _length + addtionalLength + overReservedLength;
        if (_longData.length < capacity)
            _longData.length = capacity;
        _longData[0.._length] = _shortData[0.._length];
    }

private:
    enum overReservedLength = 1_000u;
    size_t _length;
    Char[] _longData;
    Char[Size] _shortData = 0;
}

template ShortStringBuffer(Char)
if (isSomeChar!Char || isIntegral!Char)
{
    enum overheadSize = ShortStringBufferSize!(Char, 1).sizeof;
    alias ShortStringBuffer = ShortStringBufferSize!(Char, 256u - overheadSize);
}


// Any below codes are private
private:

nothrow @safe unittest // inplaceMoveToLeft
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.utf8.inplaceMoveToLeft");

    auto chars = cast(ubyte[])"1234567890".dup;
    inplaceMoveToLeft(chars, 5, 0, 5);
    assert(chars == "6789067890");
}

nothrow @safe unittest // NumericLexer
{
    import std.utf : byCodeUnit;
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.utf8.NumericLexer");

    NumericLexer!(typeof("".byCodeUnit)) r;

    assert(r.isDigitChar('0'));
    assert(r.isDigitChar('9'));
    assert(!r.isDigitChar('a'));

    assert(r.isHexChar('0'));
    assert(r.isHexChar('9'));
    assert(r.isHexChar('a'));
    assert(r.isHexChar('A'));
    assert(r.isHexChar('f'));
    assert(r.isHexChar('F'));
    assert(!r.isHexChar('g'));

    assert(r.toUpper('A') == 'A');
    assert(r.toUpper('a') == 'A');
    assert(r.toUpper('z') == 'Z');
}

@safe unittest // ShortStringBufferSize
{
    import pham.utl.test;
    traceUnitTest("unittest pham.utl.utf8.ShortStringBufferSize");

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
    traceUnitTest("unittest pham.utl.utf8.ShortStringBufferSize.reverse");

    ShortStringBufferSize!(int, 3) a;

    a.clear().put([1, 2]);
    assert(a.reverse()[] == [2, 1]);

    a.clear().put([1, 2, 3, 4, 5]);
    assert(a.reverse()[] == [5, 4, 3, 2, 1]);
}
