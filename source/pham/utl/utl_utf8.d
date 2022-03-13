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
import std.range.primitives : ElementType, empty, front, isInfinite, isInputRange, isOutputRange, popFront, put, save;
import std.traits : isIntegral, isSigned, isSomeChar, isSomeString, isUnsigned, Unqual;

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

/**
 * Check and convert a 'c' from digit to byte
 * Params:
 *  c = a charater to be checked and converted
 *  b = byte presentation of c's value if valid
 * Returns:
 *  true if c is a valid digit characters, false otherwise
 */
pragma(inline, true)
bool isDigit(const(dchar) c, ref ubyte b) @nogc nothrow pure @safe
{
    if (c >= '0' && c <= '9')
    {
        b = cast(ubyte)(c - '0');
        return true;
    }
    else
        return false;
}

version (none)
bool isDigit(const(char) c, ref ubyte b) @nogc nothrow pure @safe
{
    if (c >= '0' && c <= '9')
    {
        b = cast(ubyte)(c - '0');
        return true;
    }
    else
        return false;
}

/**
 * Check and convert a 'c' from hex to byte
 * Params:
 *  c = a charater to be checked and converted
 *  b = byte presentation of c's value if valid
 * Returns:
 *  true if c is a valid hex characters, false otherwise
 */
//pragma(inline, true)
bool isHexDigit(const(dchar) c, ref ubyte b) @nogc nothrow pure @safe
{
    if (c >= '0' && c <= '9')
        b = cast(ubyte)(c - '0');
    else if (c >= 'A' && c <= 'F')
        b = cast(ubyte)((c - 'A') + 10);
    else if (c >= 'a' && c <= 'f')
        b = cast(ubyte)((c - 'a') + 10);
    else
        return false;

    return true;
}

version (none)
bool isHexDigit(const(char) c, ref ubyte b) @nogc nothrow pure @safe
{
    if (c >= '0' && c <= '9')
        b = cast(ubyte)(c - '0');
    else if (c >= 'A' && c <= 'F')
        b = cast(ubyte)((c - 'A') + 10);
    else if (c >= 'a' && c <= 'f')
        b = cast(ubyte)((c - 'a') + 10);
    else
        return false;

    return true;
}

bool nextUTF8Char(scope const(char)[] str, size_t pos, out dchar cCode, out ubyte cCount) @nogc nothrow pure @safe
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
            // Return max count to avoid buffer overrun
            while (cCount + pos - 1 > str.length)
                cCount--;

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

version (none)
pragma(inline, true)
bool isUTF16SurrogateHigh(const(wchar) c) @nogc nothrow pure @safe
{
    enum unicodeSurrogateHighBegin = 0xD800;
    enum unicodeSurrogateHighEnd = 0xDBFF;
    return c >= unicodeSurrogateHighBegin && c <= unicodeSurrogateHighEnd;
}

version (none)
pragma(inline, true)
bool isUTF16SurrogateLow(const(wchar) c) @nogc nothrow pure @safe
{
    enum unicodeSurrogateLowBegin = 0xDC00;
    enum unicodeSurrogateLowEnd = 0xDFFF;
    return c >= unicodeSurrogateLowBegin && c <= unicodeSurrogateLowEnd;
}

bool nextUTF16Char(scope const(wchar)[] str, size_t pos, out dchar cCode, out ubyte cCount) @nogc nothrow pure @safe
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

enum NumericLexerFlag : int
{
    skipLeadingBlank = 1 << 0, /// Skip leading space chars
    skipTrailingBlank = 1 << 1, /// Skip trailing space chars
    skipInnerBlank = 1 << 2, /// Skip inner space chars
    allowFloat = 1 << 3, /// Allow input to be a float
    allowHexDigit = 1 << 4, /// Allow input to be hex digits
    hexDigit = 1 << 5, /// Consider input as hex digits
    unsigned = 1 << 6, /// Consider input as unsigned value
}

struct NumericLexerOptions(Char)
if (isSomeChar!Char)
{
nothrow @safe:

    /// Skip these characters, set to null to if not used
    Char[] groupSeparators = ['_'];
    NumericLexerFlag flags = NumericLexerFlag.skipLeadingBlank | NumericLexerFlag.skipTrailingBlank;
    Char decimalChar = '.';

    pragma(inline, true)
    bool canContinueSkippingSpaces() const @nogc pure
    {
        return (flags & (NumericLexerFlag.skipTrailingBlank | NumericLexerFlag.skipInnerBlank)) != 0;
    }

    pragma(inline, true)
    bool canSkippingLeadingBlank() const @nogc pure
    {
        return (flags & NumericLexerFlag.skipLeadingBlank) != 0;
    }

    pragma(inline, true)
    bool canSkippingInnerBlank() const @nogc pure
    {
        return (flags & NumericLexerFlag.skipInnerBlank) != 0;
    }

    pragma(inline, true)
    bool canSkippingTrailingBlank() const @nogc pure
    {
        return (flags & NumericLexerFlag.skipTrailingBlank) != 0;
    }

    pragma(inline, true)
    bool isContinueSkippingChar(const(Char) c) const @nogc pure
    {
        return isGroupSeparator(c) || (canSkippingInnerBlank() && isSpaceChar(c));
    }

    pragma(inline, true)
    bool isDecimalChar(const(Char) c) const @nogc pure
    {
        return c == decimalChar;
    }

    bool isGroupSeparator(const(Char) c) const @nogc pure
    {
        foreach (i; 0..groupSeparators.length)
        {
            if (c == groupSeparators[i])
                return true;
        }
        return false;
    }

    static bool isHexDigitPrefix(scope const(Char)[] hexDigits) @nogc pure
    {
        return hexDigits.length >= 2 && hexDigits[0] == '0' && (hexDigits[1] == 'x' || hexDigits[1] == 'X');
    }

    pragma (inline, true)
    bool isSpaceChar(const(Char) c) const @nogc pure
    {
        return c == ' '
                || c == '\r'
                || c == '\n'
                || c == '\f'
                || c == '\t'
                || c == '\v'
                || isGroupSeparator(c);
    }
}

enum bool isNumericLexerRange(Range) = isInputRange!Range && isSomeChar!(ElementType!Range) && !isInfinite!Range;

struct NumericLexer(Range)
if (isNumericLexerRange!Range)
{
nothrow @safe:

public:
    alias RangeElement = Unqual!(ElementType!Range);

public:
    @disable this(this);

    this(Range value, NumericLexerOptions!(ElementType!Range) options) pure
    {
        this.value = value;
        this.options = options;
        this._hasDecimalChar = this._hasNumericChar = this._hasHexDigitPrefix = this._neg = false;
        checkHasNumericChar();
    }

    pragma(inline, true)
    bool allowDecimalChar() const @nogc pure
    {
        return !_hasDecimalChar && (options.flags & NumericLexerFlag.allowFloat);
    }

    pragma(inline, true)
    bool canContinueSkippingSpaces() const @nogc pure
    {
        return options.canContinueSkippingSpaces();
    }

    pragma(inline, true)
    bool isInvalidAfterContinueSkippingSpaces() const @nogc pure
    {
        return options.canSkippingTrailingBlank && !empty;
    }

    pragma(inline, true)
    bool isNumericFront(ref ubyte b) const pure
    in
    {
        assert(!empty);
    }
    do
    {
        return isNumericFrontFct(front, b);
    }

    void popDecimalChar() pure
    in
    {
        assert(!empty);
        assert(front == options.decimalChar);
    }
    do
    {
        _hasDecimalChar = true;
        popFront();
    }

    //pragma(inline, true)
    void popFront() pure
    {
        scope (failure) assert(0);

        if (_hasSavedFront)
            _hasSavedFront = false;
        else
            value.popFront();
        _count++;

        while (!value.empty && options.isGroupSeparator(value.front))
        {
            value.popFront();
            _count++;
        }
    }

    void skipSpaces() pure
    {
        while (!empty && options.isSpaceChar(front))
            popFront();
    }

    static RangeElement toUpper(RangeElement c) @nogc pure
    {
        return (c >= 'a' && c <= 'z')
            ? cast(RangeElement)(c - ('a' - 'A'))
            : c;
    }

    @property size_t count() const @nogc pure
    {
        return _count;
    }

    pragma(inline, true)
    @property bool empty() const @nogc pure
    {
        return value.empty && !_hasSavedFront;
    }

    //pragma(inline, true)
    @property RangeElement front() const pure
    in
    {
        assert(!empty);
    }
    do
    {
        scope (failure) assert(0);

        return _hasSavedFront ? _savedFront : value.front;
    }

    @property bool hasHexDigitPrefix() const @nogc pure
    {
        return _hasHexDigitPrefix;
    }

    @property bool hasNumericChar() const @nogc pure
    {
        return _hasNumericChar;
    }

    @property bool neg() const @nogc pure
    {
        return _neg;
    }

public:
    Range value;
    NumericLexerOptions!(ElementType!Range) options;
    bool function(const(dchar) c, ref ubyte b) @nogc nothrow pure @safe isNumericFrontFct;

private:
    void checkHasNumericChar() pure
    {
        scope (failure) assert(0);

        _hasSavedFront = false;
        isNumericFrontFct = (options.flags & NumericLexerFlag.hexDigit) != 0 ? &isHexDigit : &isDigit;

        if (options.canSkippingLeadingBlank)
        {
            skipSpaces();
            if (value.empty)
                return;
        }

        const c = value.front;
        if (c == '-')
        {
            _neg = true;
            _count++;
            value.popFront();
        }
        else if (c == '+')
        {
            _count++;
            value.popFront();
        }
        else if (c == '0' && (options.flags & NumericLexerFlag.allowHexDigit))
        {
            _savedFront = c;
            _hasSavedFront = true;
            _hasNumericChar = true;
            value.popFront(); // No increment _count because of _hasSavedFront
            if (value.empty)
                return;

            const x = value.front;
            if (x == 'x' || x == 'X')
            {
                isNumericFrontFct = &isHexDigit;
                _hasHexDigitPrefix = true;
                _hasSavedFront = false;
                _hasNumericChar = false;
                _count++; // Skip _hasSavedFront
                popFront(); // Pop x
            }
            else
                return;
        }

        if (value.empty)
            return;

        ubyte b = void;
        const c2 = value.front;
        _hasNumericChar = isNumericFrontFct(c2, b) || (isDigit(c2, b) | (allowDecimalChar() && options.isDecimalChar(c2)));
    }

private:
    size_t _count;
    RangeElement _savedFront = 0;
    bool _hasDecimalChar, _hasNumericChar, _hasHexDigitPrefix, _hasSavedFront, _neg;
}

struct NumericStringRange(S)
if (isSomeString!S)
{
@nogc nothrow pure @safe:

public:
    this(S str)
    {
        this.str = str;
    }

    pragma(inline, true)
    void popFront()
    in
    {
        assert(!empty);
    }
    do
    {
        i++;
    }

    typeof(this) save() const
    {
        typeof(this) result = this;
        return result;
    }

    pragma(inline, true)
    @property bool empty() const
    {
        return i >= str.length;
    }

    pragma(inline, true)
    @property ElementType!S front() const
    in
    {
        assert(!empty);
    }
    do
    {
        return str[i];
    }

    pragma(inline, true)
    @property size_t length() const
    {
        return str.length - i;
    }

private:
    size_t i;
    S str;
}

enum NumericParsedKind : ubyte
{
    ok,
    invalid,
    overflow,
}

NumericLexerOptions!Char defaultParseDecimalOptions(Char)() nothrow pure @safe
{
    NumericLexerOptions!Char result;
    result.flags |= NumericLexerFlag.allowFloat;
    return result;
}

NumericLexerOptions!Char defaultParseHexDigitOptions(Char)() nothrow pure @safe
{
    NumericLexerOptions!Char result;
    result.flags |= NumericLexerFlag.hexDigit | NumericLexerFlag.allowHexDigit;
    return result;
}

NumericLexerOptions!Char defaultParseIntegralOptions(Char)() nothrow pure @safe
{
    NumericLexerOptions!Char result;
    result.flags |= NumericLexerFlag.allowHexDigit;
    return result;
}

/**
 * Parse 'hexText' to integral value
 * Params:
 *  hexText = character range to be converted
 *  v = integral presentation of hexText
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseHexDigits(Range, Target)(ref Range hexText, out Target v) nothrow pure @safe
if (isNumericLexerRange!Range && isIntegral!Target)
{
    v = 0;

    auto lexer = NumericLexer!Range(hexText, defaultParseHexDigitOptions!(ElementType!Range)());
    if (!lexer.hasNumericChar)
        return NumericParsedKind.invalid;

    size_t count = 0;
    while (!lexer.empty)
    {
        ubyte b = void;
        const c = lexer.front;
        if (isHexDigit(c, b))
        {
            if (count == Target.sizeof*2)
                return NumericParsedKind.overflow;

            v = cast(Target)((v << 4) | b);
            count++;
            lexer.popFront();
        }
        else if (lexer.options.isSpaceChar(c) && lexer.canContinueSkippingSpaces())
        {
            lexer.skipSpaces();
            if (lexer.isInvalidAfterContinueSkippingSpaces())
                return NumericParsedKind.invalid;
        }
        else
            return NumericParsedKind.invalid;
    }

    return NumericParsedKind.ok;
}

///dito
NumericParsedKind parseHexDigits(S, Target)(scope S hexText, out Target v) nothrow pure @safe
if (isSomeString!S && isIntegral!Target)
{
    auto range = NumericStringRange!S(hexText);
    return parseHexDigits(range, v);
}

/**
 * Parse 'hexText' to ubyte[] sink
 * Params:
 *  hexText = character range to be converted
 *  sink = sink to hold ubytes
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseHexDigits(Range, Writer)(ref Range hexDigitText, ref Writer sink) nothrow pure @safe
if (isNumericLexerRange!Range && isOutputRange!(Writer, ubyte))
{
    auto lexer = NumericLexer!Range(hexDigitText, defaultParseHexDigitOptions!(ElementType!Range)());
    if (!lexer.hasNumericChar)
        return NumericParsedKind.invalid;

    bool bc = false;
    ubyte bv = 0;
    while (!lexer.empty)
    {
        ubyte b = void;
        const c = lexer.front;
        if (isHexDigit(c, b))
        {
            bv = cast(ubyte)((bv << 4) | b);
            if (bc)
            {
                put(sink, bv);
                bv = 0;
                bc = false;
            }
            else
                bc = true;
            lexer.popFront();
        }
        else if (lexer.options.isSpaceChar(c) && lexer.canContinueSkippingSpaces())
        {
            lexer.skipSpaces();
            if (lexer.isInvalidAfterContinueSkippingSpaces())
                return NumericParsedKind.invalid;
        }
        else
            return NumericParsedKind.invalid;
    }
    if (bc)
        put(sink, bv);
    return NumericParsedKind.ok;
}

///dito
NumericParsedKind parseHexDigits(S, Writer)(scope S hexDigitText, ref Writer sink) nothrow pure @safe
if (isSomeString!S && isOutputRange!(Writer, ubyte))
{
    auto range = NumericStringRange!S(hexDigitText);
    return parseHexDigits(range, v);
}

/**
 * Parse 'integralText' to integral value
 * Params:
 *  integralText = character range to be converted
 *  v = integral presentation of integralText
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseIntegral(Range, Target)(ref Range integralText, out Target v) nothrow pure @safe
if (isNumericLexerRange!Range && isIntegral!Target)
{
    v = 0;

    auto lexer = NumericLexer!Range(integralText, defaultParseIntegralOptions!(ElementType!Range)());
    if (!lexer.hasNumericChar)
        return NumericParsedKind.invalid;

    static if (isUnsigned!Target)
    if (lexer.neg)
        return NumericParsedKind.invalid;

    if (lexer.hasHexDigitPrefix)
    {
        size_t count = 0;
        while (!lexer.empty)
        {
            ubyte b = void;
            const c = lexer.front;
            if (isHexDigit(c, b))
            {
                if (count == Target.sizeof*2)
                    return NumericParsedKind.overflow;

                count++;
                v = cast(Target)((v << 4) | b);
                lexer.popFront();
            }
            else if (lexer.options.isSpaceChar(c) && lexer.canContinueSkippingSpaces())
            {
                lexer.skipSpaces();
                if (lexer.isInvalidAfterContinueSkippingSpaces())
                    return NumericParsedKind.invalid;
            }
            else
                return NumericParsedKind.invalid;
        }
    }
    else
    {
        const maxLastDigit = (Target.min < 0 ? 7 : 5) + lexer.neg;

        static if (Target.sizeof <= int.sizeof)
            int vTemp = 0;
        else
            long vTemp = 0;

        while (!lexer.empty)
        {
            ubyte b = void;
            const c = lexer.front;
            if (isDigit(c, b))
            {
                enum maxDiv10 = Target.max/10;
                if (vTemp >= 0 && (vTemp < maxDiv10 || (vTemp == maxDiv10 && b <= maxLastDigit)))
                {
                    vTemp = (vTemp * 10) + b;
                    lexer.popFront();
                }
                else
                    return NumericParsedKind.overflow;
            }
            else if (lexer.options.isSpaceChar(c) && lexer.canContinueSkippingSpaces())
            {
                lexer.skipSpaces();
                if (lexer.isInvalidAfterContinueSkippingSpaces())
                    return NumericParsedKind.invalid;
            }
            else
                return NumericParsedKind.invalid;
        }

        static if (isSigned!Target)
        if (lexer.neg)
            vTemp = -vTemp;

        v = cast(Target)vTemp;
    }

    return NumericParsedKind.ok;
}

///dito
NumericParsedKind parseIntegral(S, Target)(scope S integralText, out Target v) nothrow pure @safe
if (isSomeString!S && isIntegral!Target)
{
    auto range = NumericStringRange!S(integralText);
    return parseIntegral(range, v);
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

    this(bool setShortSize) nothrow pure
    {
        if (setShortSize)
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

    inout(T)[] opIndex() inout nothrow pure return
    {
        return useShortSize ? _shortData[0.._length] : _longData[0.._length];
    }

    T opIndex(const(size_t) i) const @nogc nothrow pure
    in
    {
        assert(i < length);
    }
    do
    {
        return useShortSize ? _shortData[i] : _longData[i];
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

    ref typeof(this) opIndexAssign(T c, const(size_t) i) @nogc nothrow return
    in
    {
        assert(i < length);
    }
    do
    {
        if (useShortSize)
            _shortData[i] = c;
        else
            _longData[i] = c;
        return this;
    }

    static if (isIntegral!T)
    ref typeof(this) opIndexOpAssign(string op)(T c, const(size_t) i) @nogc nothrow pure
    if (op == "&" || op == "|" || op == "^")
    in
    {
        assert(i < length);
    }
    do
    {
        if (useShortSize)
            mixin("_shortData[i] " ~ op ~ "= c;");
        else
            mixin("_longData[i] " ~ op ~ "= c;");
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

    ref typeof(this) clear(bool setShortSize = false)() nothrow pure
    {
        _length = 0;
        static if (setShortSize)
        {
            _shortData[] = 0;
            _longData[] = 0;
            _length = ShortSize;
        }
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

        enum bugChecklimit = 1024 * 1024 * 4; // 4MB
        assert(newLength <= bugChecklimit);

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
    size_t alignAddtionalLength(const(size_t) addtionalLength) @nogc nothrow pure
    {
        if (addtionalLength <= overReservedLength)
            return overReservedLength;
        else
            return ((addtionalLength + overReservedLength - 1) / overReservedLength) * overReservedLength;
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

    void switchToLongData(const(size_t) addtionalLength) nothrow pure
    {
        const capacity = alignAddtionalLength(_length + addtionalLength);
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
    enum overheadSize = ShortStringBufferSize!(T, 1).sizeof;
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

nothrow @safe unittest // isDigit
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.isDigit");

    ubyte b;

    assert(isDigit('0', b));
    assert(b == 0);

    assert(isDigit('1', b));
    assert(b == 1);

    assert(isDigit('9', b));
    assert(b == 9);

    assert(!isDigit('a', b));
}

nothrow @safe unittest // isHexDigit
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.isHexDigit");

    ubyte b;

    assert(isHexDigit('0', b));
    assert(b == 0);

    assert(isHexDigit('9', b));
    assert(b == 9);

    assert(isHexDigit('a', b));
    assert(b == 10);

    assert(isHexDigit('F', b));
    assert(b == 15);

    assert(!isHexDigit('z', b));
}

nothrow @safe unittest // NumericLexerOptions.isHexDigitPrefix
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.NumericLexerOptions.isHexDigitPrefix");

    enum t1 = NumericLexerOptions!char.isHexDigitPrefix("0x0");
    enum t2 = NumericLexerOptions!char.isHexDigitPrefix("0X0");

    assert(!NumericLexerOptions!char.isHexDigitPrefix("x0"));
    assert(!NumericLexerOptions!char.isHexDigitPrefix("0"));
    assert(!NumericLexerOptions!char.isHexDigitPrefix("012"));
}

nothrow @safe unittest // NumericLexer
{
    import std.utf : byCodeUnit;
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.NumericLexer");

    NumericLexer!(typeof("".byCodeUnit)) r;

    assert(r.toUpper('A') == 'A');
    assert(r.toUpper('a') == 'A');
    assert(r.toUpper('z') == 'Z');
}

nothrow @safe unittest // parseIntegral, parseHexDigits
{
    import std.conv : to;
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.parseIntegral, parseHexDigits");

    int i;

    assert(parseIntegral("0", i) == NumericParsedKind.ok); assert(i == 0);
    assert(parseIntegral("0123456789", i) == NumericParsedKind.ok); assert(i == 123456789);

    assert(parseIntegral("0x01fAc764", i) == NumericParsedKind.ok); assert(i == 0x1fAc764);
    assert(parseHexDigits("0x01fAc764", i) == NumericParsedKind.ok); assert(i == 0x1fAc764);
    assert(parseHexDigits("01fAc764", i) == NumericParsedKind.ok); assert(i == 0x1fAc764);

    assert(parseIntegral("", i) == NumericParsedKind.invalid);
    assert(parseIntegral("0ab", i) == NumericParsedKind.invalid);
    assert(parseIntegral("123 456", i) == NumericParsedKind.invalid);
    assert(parseHexDigits("", i) == NumericParsedKind.invalid);
    assert(parseHexDigits("0x0abxyz", i) == NumericParsedKind.invalid);
    assert(parseHexDigits("0x0 abc", i) == NumericParsedKind.invalid);

    assert(parseIntegral(to!string(long.max), i) == NumericParsedKind.overflow);
    assert(parseIntegral(to!string(long.min), i) == NumericParsedKind.overflow);
    assert(parseIntegral("0x1234567890", i) == NumericParsedKind.overflow);
    assert(parseHexDigits("0x1234567890", i) == NumericParsedKind.overflow);
}

nothrow @safe unittest // parseIntegral
{
    import std.conv : to;
    import std.meta : AliasSeq;
    import std.traits : isSigned, isUnsigned;
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.utf8.parseIntegral");

    static foreach (I; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong))
    {
        {
            I i1;

            assert(parseIntegral("0", i1) == NumericParsedKind.ok); assert(i1 == 0);
            assert(parseIntegral(to!string(I.min), i1) == NumericParsedKind.ok); assert(i1 == I.min);
            assert(parseIntegral(to!string(I.max), i1) == NumericParsedKind.ok); assert(i1 == I.max);

            static if (isSigned!I)
            {
                assert(parseIntegral("+0", i1) == NumericParsedKind.ok); assert(i1 == 0);
                assert(parseIntegral("-0", i1) == NumericParsedKind.ok); assert(i1 == 0);
            }
        }

        static if (I.sizeof >= byte.sizeof)
        {{
            I i2;

            assert(parseIntegral("6", i2) == NumericParsedKind.ok); assert(i2 == 6);
            assert(parseIntegral("23", i2) == NumericParsedKind.ok); assert(i2 == 23);
            assert(parseIntegral("68", i2) == NumericParsedKind.ok); assert(i2 == 68);
            assert(parseIntegral("127", i2) == NumericParsedKind.ok); assert(i2 == 127);

            static if (isUnsigned!I)
            {
                assert(parseIntegral("255", i2) == NumericParsedKind.ok); assert(i2 == 0xFF);
                assert(parseIntegral("0xfF", i2) == NumericParsedKind.ok); assert(i2 == 0xFF);
            }

            static if (isSigned!I)
            {
                assert(parseIntegral("+6", i2) == NumericParsedKind.ok); assert(i2 == 6);
                assert(parseIntegral("+23", i2) == NumericParsedKind.ok); assert(i2 == 23);
                assert(parseIntegral("+68", i2) == NumericParsedKind.ok); assert(i2 == 68);
                assert(parseIntegral("+127", i2) == NumericParsedKind.ok); assert(i2 == 127);

                assert(parseIntegral("-6", i2) == NumericParsedKind.ok); assert(i2 == -6);
                assert(parseIntegral("-23", i2) == NumericParsedKind.ok); assert(i2 == -23);
                assert(parseIntegral("-68", i2) == NumericParsedKind.ok); assert(i2 == -68);
                assert(parseIntegral("-128", i2) == NumericParsedKind.ok); assert(i2 == -128);
            }
        }}

        static if (I.sizeof >= short.sizeof)
        {{
            I i3;

            assert(parseIntegral("468", i3) == NumericParsedKind.ok); assert(i3 == 468);
            assert(parseIntegral("32767", i3) == NumericParsedKind.ok); assert(i3 == 32767);

            static if (isUnsigned!I)
            {
                assert(parseIntegral("65535", i3) == NumericParsedKind.ok); assert(i3 == 0xFFFF);
                assert(parseIntegral("0xFFFF", i3) == NumericParsedKind.ok); assert(i3 == 0xFFFF);
            }

            static if (isSigned!I)
            {
                assert(parseIntegral("+468", i3) == NumericParsedKind.ok); assert(i3 == 468);
                assert(parseIntegral("+32767", i3) == NumericParsedKind.ok); assert(i3 == 32767);

                assert(parseIntegral("-468", i3) == NumericParsedKind.ok); assert(i3 == -468);
                assert(parseIntegral("-32768", i3) == NumericParsedKind.ok); assert(i3 == -32768);
            }
        }}

        static if (I.sizeof >= int.sizeof)
        {{
            I i4;

            assert(parseIntegral("2147483647", i4) == NumericParsedKind.ok); assert(i4 == 2147483647);

            static if (isUnsigned!I)
            {
                assert(parseIntegral("4294967295", i4) == NumericParsedKind.ok); assert(i4 == 0xFFFFFFFF);
                assert(parseIntegral("0xFFFFFFFF", i4) == NumericParsedKind.ok); assert(i4 == 0xFFFFFFFF);
            }

            static if (isSigned!I)
            {
                assert(parseIntegral("+2147483647", i4) == NumericParsedKind.ok); assert(i4 == 2147483647);
                assert(parseIntegral("-2147483648", i4) == NumericParsedKind.ok); assert(i4 == -2147483648);
            }
        }}

        static if (I.sizeof >= long.sizeof)
        {{
            I i5;

            assert(parseIntegral("9223372036854775807", i5) == NumericParsedKind.ok); assert(i5 == 0x7FFFFFFFFFFFFFFF);
            assert(parseIntegral("0x7FFFFFFFFFFFFFFF", i5) == NumericParsedKind.ok); assert(i5 == 0x7FFFFFFFFFFFFFFF);

            static if (isUnsigned!I)
            {
                assert(parseIntegral("18446744073709551615", i5) == NumericParsedKind.ok); assert(i5 == 0xFFFFFFFFFFFFFFFF);
                assert(parseIntegral("0xFFFFFFFFFFFFFFFF", i5) == NumericParsedKind.ok); assert(i5 == 0xFFFFFFFFFFFFFFFF);
            }

            static if (isSigned!I)
            {
                assert(parseIntegral("+9223372036854775807", i5) == NumericParsedKind.ok); assert(i5 == 0x7FFFFFFFFFFFFFFF);
                assert(parseIntegral("-9223372036854775808", i5) == NumericParsedKind.ok); assert(i5 == 0x8000000000000000);

                assert(parseIntegral("0x7FFFFFFFFFFFFFFF", i5) == NumericParsedKind.ok); assert(i5 == 0x7FFFFFFFFFFFFFFF);
                assert(parseIntegral("0x8000000000000000", i5) == NumericParsedKind.ok); assert(i5 == 0x8000000000000000);
            }
        }}
    }
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
