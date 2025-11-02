/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2022 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_numeric_parser;

import core.time : Duration, dur;
public import std.ascii : LetterCase;
import std.range.primitives : isInfinite, isInputRange, isOutputRange, put;
import std.traits : Unqual, isIntegral, isSigned, isSomeChar, isSomeString, isUnsigned;

debug(debug_pham_utl_utl_numeric_parser) import std.stdio : writeln;
import pham.utl.utl_range;
import pham.utl.utl_utf8;

nothrow @safe:

enum Base64MappingChar : char
{
    map62th = '+',
    map63th = '/',
    padding = '=',
    noPadding = '\0',
}

/**
 * Convert byte array to its base64 presentation
 * Params:
 *  bytes = bytes to be converted
 *  padding = a padding character; use Base64MappingChar.noPadding to avoid adding padding character
 *  isLineBreak = should adding '\n' for each 80 base64 characters?
 * Returns:
 *  array of base64 characters
 */
char[] cvtBytesBase64(bool lineBreak = false)(scope const(ubyte)[] bytes,
    const(char) padding = Base64MappingChar.padding,
    const(uint) lineBreakLength = 80) pure
{
    import pham.utl.utl_array_append : Appender;

    if (bytes.length == 0)
        return null;

    auto buffer = Appender!(char[])(cvtBytesBase64Length(bytes.length, lineBreak, lineBreakLength, padding));
    return cvtBytesBase64!(Appender!(char[]), lineBreak)(buffer, bytes, padding, lineBreakLength)[];
}

ref Writer cvtBytesBase64(Writer, bool lineBreak = false)(return ref Writer sink, scope const(ubyte)[] bytes,
    const(char) padding = Base64MappingChar.padding,
    const(uint) lineBreakLength = 80) pure @trusted
if (isOutputRange!(Writer, char))
{
    if (bytes.length == 0)
        return sink;

    static immutable encodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        ~ Base64MappingChar.map62th ~ Base64MappingChar.map63th;
    enum lineBreakChar = '\n';

    size_t resultLineBreak = 0;
    auto bytesPtr = &bytes[0];
    const blocks = bytes.length / 3;
    foreach (_; 0..blocks)
    {
        static if (lineBreak)
        {
            if (resultLineBreak >= lineBreakLength)
            {
                resultLineBreak = 0;
                put(sink, lineBreakChar);
            }
        }

        const val = (bytesPtr[0] << 16) | (bytesPtr[1] << 8) | bytesPtr[2];
        put(sink, encodeMap[val >> 18       ]);
        put(sink, encodeMap[val >> 12 & 0x3f]);
        put(sink, encodeMap[val >>  6 & 0x3f]);
        put(sink, encodeMap[val       & 0x3f]);
        bytesPtr += 3;

        static if (lineBreak)
            resultLineBreak += 4;
    }

    const remain = bytes.length % 3;
    if (remain)
    {
        const val = (bytesPtr[0] << 16) | (remain == 2 ? bytesPtr[1] << 8 : 0);
        put(sink, encodeMap[val >> 18       ]);
        put(sink, encodeMap[val >> 12 & 0x3f]);

        final switch (remain)
        {
            case 2:
                put(sink, encodeMap[val >> 6 & 0x3f]);
                if (padding != Base64MappingChar.noPadding)
                    put(sink, padding);
                break;
            case 1:
                if (padding != Base64MappingChar.noPadding)
                {
                    put(sink, padding);
                    put(sink, padding);
                }
                break;
        }
    }

    return sink;
}

size_t cvtBytesBase64Length(const(size_t) bytes,
    const(bool) lineBreak = false, const(uint) lineBreakLength = 80,
    const(char) padding = Base64MappingChar.padding) @nogc pure
{
    const mod3 = bytes % 3;
    const res = padding == Base64MappingChar.noPadding
        ? ((bytes / 3) * 4 + (mod3 == 0 ? 0 : (mod3 == 1 ? 2 : 3)))
        : ((bytes / 3 + (mod3 ? 1 : 0)) * 4);
    return res + (lineBreak ? lineBreakCount(res, lineBreakLength) : 0);
}

/**
 * Convert byte array to its hex presentation
 * lineBreak = should adding '\n' for each lineBreakLength hex characters?
 * Params:
 *  bytes = bytes to be converted
 *  letterCase = use upper or lower case letters
 * Returns:
 *  array of hex characters
 */
char[] cvtBytesBase16(bool lineBreak = false)(scope const(ubyte)[] bytes,
    const(LetterCase) letterCase = LetterCase.upper,
    const(uint) lineBreakLength = 80) pure
{
    import pham.utl.utl_array_append : Appender;

    if (bytes.length == 0)
        return null;

    auto buffer = Appender!(char[])(cvtBytesBase16Length(bytes.length, lineBreak, lineBreakLength));
    return cvtBytesBase16!(Appender!(char[]), lineBreak)(buffer, bytes, letterCase, lineBreakLength)[];
}

ref Writer cvtBytesBase16(Writer, bool lineBreak = false)(return ref Writer sink, scope const(ubyte)[] bytes,
    const(LetterCase) letterCase = LetterCase.upper,
    const(uint) lineBreakLength = 80) pure
if (isOutputRange!(Writer, char))
{
    import std.ascii : lowerHexDigits, upperHexDigits=hexDigits;

    if (bytes.length == 0)
        return sink;

    const hexDigits = letterCase == LetterCase.upper ? upperHexDigits : lowerHexDigits;
    enum lineBreakChar = '\n';

    size_t resultLineBreak = 0;
    foreach (b; bytes)
    {
        static if (lineBreak)
        {
            if (resultLineBreak >= lineBreakLength)
            {
                resultLineBreak = 0;
                put(sink, lineBreakChar);
            }
        }

        put(sink, hexDigits[(b >> 4) & 0xF]);
        put(sink, hexDigits[b & 0xF]);

        static if (lineBreak)
            resultLineBreak += 2;
    }

    return sink;
}

size_t cvtBytesBase16Length(const(size_t) bytes,
    const(bool) lineBreak = false, const(uint) lineBreakLength = 80) @nogc pure
{
    const res = bytes * 2;
    return res + (lineBreak ? lineBreakCount(res, lineBreakLength) : 0);
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
bool cvtDigit(Char)(const(Char) c, ref ubyte b) @nogc pure
if (isSomeChar!Char)
{
    if (c >= '0' && c <= '9')
    {
        b = cast(ubyte)(c - '0');
        return true;
    }
    else
        return false;
}

pragma(inline, true)
ubyte cvtDigit2(Char)(const(Char) c) @nogc pure
if (isSomeChar!Char)
in
{
    assert(isDigit(c));
}
do
{
    return cast(ubyte)(c - '0');
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
bool cvtHexDigit(Char)(const(Char) c, ref ubyte b) @nogc pure
if (isSomeChar!Char)
{
    if (c >= '0' && c <= '9')
    {
        b = cast(ubyte)(c - '0');
        return true;
    }
    else if (c >= 'A' && c <= 'F')
    {
        b = cast(ubyte)((c - 'A') + 10);
        return true;
    }
    else if (c >= 'a' && c <= 'f')
    {
        b = cast(ubyte)((c - 'a') + 10);
        return true;
    }
    else
        return false;
}

//pragma(inline, true)
ubyte cvtHexDigit2(Char)(const(Char) c) @nogc pure
if (isSomeChar!Char)
in
{
    assert(isHexDigit(c));
}
do
{
    if (c >= '0' && c <= '9')
        return cast(ubyte)(c - '0');
    else if (c >= 'A' && c <= 'F')
        return cast(ubyte)((c - 'A') + 10);
    else //if (c >= 'a' && c <= 'f')
        return cast(ubyte)((c - 'a') + 10);
}

/**
 * Return true if 'c' is a digit character
 * 0123456789
 */
pragma(inline, true)
bool isDigit(Char)(const(Char) c) @nogc pure
if (isSomeChar!Char)
{
    return c >= '0' && c <= '9';
}

/**
 * Return true if 'c' is a hex-digit character
 * 0123456789abcdfABCDF
 */
pragma(inline, true)
bool isHexDigit(Char)(const(Char) c) @nogc pure
if (isSomeChar!Char)
{
    return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f');
}

pragma(inline, true)
size_t lineBreakCount(const(size_t) charsLength, const(uint) breakLength) @nogc pure
{
    return breakLength == 0 || charsLength <= breakLength
        ? 0
        : ((charsLength - 1) / breakLength); //((charsLength / breakLength) + (charsLength % breakLength != 0));
}

enum NumericLexerFlag : uint
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
@nogc nothrow pure @safe:

    alias C = Unqual!Char;

    /// Skip these characters, set to null to if not used
    C[] groupSeparators = ['_'];
    NumericLexerFlag flags = NumericLexerFlag.skipLeadingBlank | NumericLexerFlag.skipTrailingBlank;
    C decimalChar = '.';

    pragma(inline, true)
    bool canContinueSkippingSpaces() const scope
    {
        return (flags & (NumericLexerFlag.skipTrailingBlank | NumericLexerFlag.skipInnerBlank)) != 0;
    }

    pragma(inline, true)
    bool canSkippingLeadingBlank() const scope
    {
        return (flags & NumericLexerFlag.skipLeadingBlank) != 0;
    }

    pragma(inline, true)
    bool canSkippingInnerBlank() const scope
    {
        return (flags & NumericLexerFlag.skipInnerBlank) != 0;
    }

    pragma(inline, true)
    bool canSkippingTrailingBlank() const scope
    {
        return (flags & NumericLexerFlag.skipTrailingBlank) != 0;
    }

    pragma(inline, true)
    bool isContinueSkippingChar(const(C) c) const scope
    {
        return isGroupSeparator(c) || (canSkippingInnerBlank() && isSpaceChar(c));
    }

    pragma(inline, true)
    bool isDecimalChar(const(C) c) const scope
    {
        return c == decimalChar;
    }

    bool isGroupSeparator(const(C) c) const scope
    {
        foreach (i; 0..groupSeparators.length)
        {
            if (c == groupSeparators[i])
                return true;
        }
        return false;
    }

    pragma(inline, true)
    static bool isHexDigitPrefix(scope const(C)[] hexDigits)
    {
        return hexDigits.length >= 2 && hexDigits[0] == '0' && (hexDigits[1] == 'x' || hexDigits[1] == 'X');
    }

    pragma(inline, true)
    bool isSpaceChar(const(C) c) const scope
    {
        return isSpaceCharOnly(c) || isGroupSeparator(c);
    }

    pragma(inline, true)
    static bool isSpaceCharOnly(const(C) c)
    {
        return c == ' '
            || c == '\r'
            || c == '\n'
            || c == '\f'
            || c == '\t'
            || c == '\v';
    }
}

enum isNumericLexerRange(Range) = isInputRange!Range && !isInfinite!Range && isSomeChar!(ElementType!Range);

struct Base64Lexer(Range, char map62th = Base64MappingChar.map62th, char map63th = Base64MappingChar.map63th)
if (isNumericLexerRange!Range)
{
nothrow @safe:

public:
    alias RangeElement = UElementType!Range;

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(Range value, NumericLexerOptions!(const(ElementType!Range)) options) pure
    {
        this.value = value;
        this.options = options;
        this._hasBase64Char = false;
        checkHasBase64Char();
    }

    pragma(inline, true)
    bool canContinueSkippingSpaces() const @nogc pure
    {
        return options.canContinueSkippingSpaces();
    }

    uint conditionSkipSpaces() pure
    {
        return options.canContinueSkippingSpaces() ? skipSpaces() : 0;
    }

    /**
     * Check and convert a 'c' from base64 char to byte
     * Params:
     *  c = a charater to be checked and converted
     *  b = byte presentation of c's value if valid
     * Returns:
     *  true if c is a valid base64 characters, false otherwise
     */
    pragma(inline, true)
    static bool isBase64Char(const(dchar) c, ref int b) @nogc pure
    {
        if (c <= 0x7F)
        {
            b = decodeMaps[cast(char)c];
            return b != 0 || (cast(char)c == 'A');
        }
        else
            return false;
    }

    pragma(inline, true)
    bool isBase64Front(ref int b) const pure
    in
    {
        assert(!empty);
    }
    do
    {
        return !empty && isBase64Char(front, b);
    }

    pragma(inline, true)
    bool isEndingCondition()
    {
        return empty || front == Base64MappingChar.padding;
    }

    pragma(inline, true)
    bool isInvalidAfterContinueSkippingSpaces() const @nogc pure
    {
        return !options.canSkippingInnerBlank && !empty;
    }

    void popFront() pure
    {
        value.popFront();
        _count++;

        while (!value.empty && options.isGroupSeparator(value.front))
        {
            value.popFront();
            _count++;
        }
    }

    uint skipPaddingChars() pure
    {
        uint result;
        while (!empty && front == Base64MappingChar.padding)
        {
            result++;
            popFront();
        }
        return result;
    }

    uint skipSpaces() pure
    {
        uint result;
        while (!empty && options.isSpaceChar(front))
        {
            result++;
            popFront();
        }
        return result;
    }

    @property size_t count() const @nogc pure
    {
        return _count;
    }

    //pragma(inline, true)
    @property bool empty() const @nogc pure
    {
        return value.empty;
    }

    //pragma(inline, true)
    @property RangeElement front() const pure
    in
    {
        assert(!empty);
    }
    do
    {
        return value.front;
    }

    @property bool hasBase64Char() const @nogc pure
    {
        return _hasBase64Char;
    }

public:
    Range value;
    NumericLexerOptions!(const(ElementType!Range)) options;

private:
    void checkHasBase64Char() pure
    {
        if (options.canSkippingLeadingBlank)
            skipSpaces();

        if (value.empty)
            return;

        int b = void;
        const c = value.front;
        _hasBase64Char = isBase64Char(c, b);
    }

private:
    static immutable int[char.max + 1] decodeMaps = [
        'A':0b000000, 'B':0b000001, 'C':0b000010, 'D':0b000011, 'E':0b000100,
        'F':0b000101, 'G':0b000110, 'H':0b000111, 'I':0b001000, 'J':0b001001,
        'K':0b001010, 'L':0b001011, 'M':0b001100, 'N':0b001101, 'O':0b001110,
        'P':0b001111, 'Q':0b010000, 'R':0b010001, 'S':0b010010, 'T':0b010011,
        'U':0b010100, 'V':0b010101, 'W':0b010110, 'X':0b010111, 'Y':0b011000,
        'Z':0b011001, 'a':0b011010, 'b':0b011011, 'c':0b011100, 'd':0b011101,
        'e':0b011110, 'f':0b011111, 'g':0b100000, 'h':0b100001, 'i':0b100010,
        'j':0b100011, 'k':0b100100, 'l':0b100101, 'm':0b100110, 'n':0b100111,
        'o':0b101000, 'p':0b101001, 'q':0b101010, 'r':0b101011, 's':0b101100,
        't':0b101101, 'u':0b101110, 'v':0b101111, 'w':0b110000, 'x':0b110001,
        'y':0b110010, 'z':0b110011, '0':0b110100, '1':0b110101, '2':0b110110,
        '3':0b110111, '4':0b111000, '5':0b111001, '6':0b111010, '7':0b111011,
        '8':0b111100, '9':0b111101, map62th:0b111110, map63th:0b111111,
        ];

    size_t _count;
    bool _hasBase64Char;
}

struct NumericLexer(Range)
if (isNumericLexerRange!Range)
{
nothrow @safe:

public:
    alias RangeElement = UElementType!Range;

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(Range value, NumericLexerOptions!(const(RangeElement)) options) pure
    {
        this.value = value;
        this.options = options;
        this._hasDecimalChar = this._hasNumericChar = this._hasHexDigitPrefix = this._hasSavedFront = this._isHex = this._neg = false;
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

    uint conditionSkipSpaces() pure
    {
        return options.canContinueSkippingSpaces() ? skipSpaces() : 0;
    }

    pragma(inline, true)
    bool cvtNumericFront(ref ubyte b) const pure
    in
    {
        assert(!empty);
    }
    do
    {
        return cvtNumericFrontFct(front, b);
    }

    pragma(inline, true)
    bool isInvalidAfterContinueSkippingSpaces() const @nogc pure
    {
        return !options.canSkippingInnerBlank && !empty;
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

    void popFront() pure
    {
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

    uint skipSpaces() pure
    {
        uint result;
        while (!empty && options.isSpaceChar(front))
        {
            result++;
            popFront();
        }
        return result;
    }

    uint skipSpaceOnlys() pure
    {
        uint result;
        while (!empty && options.isSpaceCharOnly(front))
        {
            result++;
            popFront();
        }
        return result;
    }

    static RangeElement toUpper(const(RangeElement) c) @nogc pure
    {
        return (c >= 'a' && c <= 'z')
            ? cast(RangeElement)(c - ('a' - 'A'))
            : c;
    }

    @property size_t count() const @nogc pure
    {
        return _count;
    }

    //pragma(inline, true)
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
        return _hasSavedFront ? _savedFront : value.front;
    }

    /**
     * Return true if range has leading 0x or 0X
     */
    @property bool hasHexDigitPrefix() const @nogc pure
    {
        return _hasHexDigitPrefix;
    }

    /**
     * Return true if range has a valid digit/hex character
     */
    @property bool hasNumericChar() const @nogc pure
    {
        return _hasNumericChar;
    }

    /**
     * Return true if range is a hex range
     */
    @property bool isHex() const @nogc pure
    {
        return _isHex;
    }

    /**
     * Return true if range has leading negative sign "-"
     */
    @property bool neg() const @nogc pure
    {
        return _neg;
    }

public:
    Range value;
    NumericLexerOptions!(const(RangeElement)) options;
    bool function(const(RangeElement), ref ubyte b) @nogc nothrow pure @safe cvtNumericFrontFct;

private:
    void checkHasNumericChar() pure
    {
        _isHex = (options.flags & NumericLexerFlag.hexDigit) != 0;
        cvtNumericFrontFct = _isHex ? &(cvtHexDigit!RangeElement) : &(cvtDigit!RangeElement);

        if (options.canSkippingLeadingBlank)
        {
            skipSpaces();
            if (empty)
                return;
        }

        RangeElement c = value.front;
        if (c == '-')
        {
            _neg = true;
            _count++;
            value.popFront();
            c = value.empty ? '\0' : value.front;
        }
        else if (c == '+')
        {
            _count++;
            value.popFront();
            c = value.empty ? '\0' : value.front;
        }

        if (c == '0' && (options.flags & NumericLexerFlag.allowHexDigit))
        {
            _savedFront = c;
            _hasNumericChar = _hasSavedFront = true;
            value.popFront(); // No increment _count because of _hasSavedFront
            if (value.empty)
                return;

            const x = value.front;
            if (x == 'x' || x == 'X')
            {
                cvtNumericFrontFct = &(cvtHexDigit!RangeElement);
                _hasHexDigitPrefix = _isHex = true;
                _hasNumericChar = _hasSavedFront = false;
                _count++; // Skip _hasSavedFront
                popFront(); // Pop x
            }
            else
                return;
        }

        if (value.empty)
            return;

        ubyte b;
        c = value.front;
        _hasNumericChar = cvtNumericFrontFct(c, b) || (allowDecimalChar() && options.isDecimalChar(c));
    }

private:
    size_t _count;
    RangeElement _savedFront = 0;
    bool _hasDecimalChar, _hasNumericChar, _hasHexDigitPrefix, _hasSavedFront, _isHex, _neg;
}

struct NumericStringRange(Char)
if (isSomeChar!Char)
{
@nogc nothrow pure @safe:

    alias C = Unqual!Char;

    this(const(C)[] str) scope
    {
        this._str = str;
        this._length = str.length;
        this._i = 0;
    }

    pragma(inline, true)
    void popBack() scope
    in
    {
        assert(!empty);
    }
    do
    {
        _length--;
    }

    pragma(inline, true)
    void popFront() scope
    in
    {
        assert(!empty);
    }
    do
    {
        _i++;
    }

    typeof(this) save() const return
    {
        return typeof(this)(_i, _length, _str);
    }

    pragma(inline, true)
    @property C back() const scope
    in
    {
        assert(!empty);
    }
    do
    {
        return _str[_length - 1];
    }

    pragma(inline, true)
    @property bool empty() const scope
    {
        return _i >= _length;
    }

    pragma(inline, true)
    @property C front() const scope
    in
    {
        assert(!empty);
    }
    do
    {
        return _str[_i];
    }

    pragma(inline, true)
    @property size_t length() const scope
    {
        return _length - _i;
    }

private:
    this(size_t i, size_t length, const(C)[] str) scope
    {
        this._i = i;
        this._length = length;
        this._str = str;
    }

private:
    size_t _i, _length;
    const(C)[] _str;
}

enum NumericParsedKind : ubyte
{
    ok,
    invalid,
    overflow,
    underflow,
}

NumericLexerOptions!(const(Char)) defaultParseBase64Options(Char)() pure
{
    NumericLexerOptions!(const(Char)) result;
    result.decimalChar = 0;
    result.groupSeparators = null;
    result.flags |= NumericLexerFlag.skipInnerBlank;
    return result;
}

NumericLexerOptions!(const(Char)) defaultParseDecimalOptions(Char)() pure
{
    NumericLexerOptions!(const(Char)) result;
    result.flags |= NumericLexerFlag.allowFloat;
    return result;
}

NumericLexerOptions!(const(Char)) defaultParseHexDigitOptions(Char)() pure
{
    NumericLexerOptions!(const(Char)) result;
    result.flags |= NumericLexerFlag.hexDigit | NumericLexerFlag.allowHexDigit;
    return result;
}

NumericLexerOptions!(const(Char)) defaultParseIntegralOptions(Char)() pure
{
    NumericLexerOptions!(const(Char)) result;
    result.flags |= NumericLexerFlag.allowHexDigit;
    return result;
}

/**
 * Parse 'hexText' to ubyte[] sink
 * Params:
 *  hexText = character range to be converted
 *  sink = sink to hold ubytes
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseBase16(Range, Writer)(ref Writer sink, scope ref Range hexDigitText) pure
if (isNumericLexerRange!Range && isOutputRange!(Writer, ubyte))
{
    auto lexer = NumericLexer!Range(hexDigitText, defaultParseHexDigitOptions!(ElementType!Range)());
    if (!lexer.hasNumericChar)
        return NumericParsedKind.invalid;

    bool bc;
    ubyte b, bv;
    while (!lexer.empty)
    {
        if (cvtHexDigit(lexer.front, b))
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
        else if (lexer.conditionSkipSpaces())
        {
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
NumericParsedKind parseBase16(String, Writer)(ref Writer sink, scope String hexDigitText) pure
if (isSomeString!String && isOutputRange!(Writer, ubyte))
{
    auto inputRange = NumericStringRange!(ElementType!String)(hexDigitText);
    return parseBase16(sink, inputRange);
}

pragma(inline, true)
size_t parseBase16Length(const(size_t) chars) @nogc pure
{
    return chars / 2;
}

/**
 * Parse 'base64Text' to ubyte[] sink
 * Params:
 *  base64Text = character range to be converted
 *  sink = sink to hold ubytes
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseBase64(Range, Writer)(ref Writer sink, scope ref Range base64Text) pure
if (isNumericLexerRange!Range && isOutputRange!(Writer, ubyte))
{
    auto lexer = Base64Lexer!(Range)(base64Text, defaultParseBase64Options!(ElementType!Range)());
    if (!lexer.hasBase64Char)
        return NumericParsedKind.invalid;

    int p, cb1, cb2;
    while (!lexer.empty)
    {
        if (lexer.isBase64Char(lexer.front, cb1))
        {
            lexer.popFront();

            if (lexer.conditionSkipSpaces() && lexer.isInvalidAfterContinueSkippingSpaces())
                return NumericParsedKind.invalid;

            if (p != 0 && lexer.skipPaddingChars() != 0)
            {
                lexer.conditionSkipSpaces();
                if (lexer.empty)
                    return NumericParsedKind.ok;
            }

            if (!lexer.isBase64Front(cb2))
                return NumericParsedKind.invalid;

            final switch (p)
            {
                case 0:
                    put(sink, cast(ubyte)((cb1 << 2) | (cb2 >> 4)));
                    break;

                case 1:
                    put(sink, cast(ubyte)(((cb1 & 0b1111) << 4)  | (cb2 >> 2)));
                    break;

                case 2:
                    put(sink, cast(ubyte)(((cb1 & 0b11) << 6) | cb2));
                    lexer.popFront();
                    break;
            }

            ++p %= 3;
        }
        else if (lexer.conditionSkipSpaces())
        {
            if (lexer.isInvalidAfterContinueSkippingSpaces())
                return NumericParsedKind.invalid;
        }
        else
        {
            lexer.skipPaddingChars();
            if (!lexer.empty)
                return NumericParsedKind.invalid;
        }
    }
    return NumericParsedKind.ok;
}

///dito
NumericParsedKind parseBase64(String, Writer)(ref Writer sink, scope String base64Text) pure
if (isSomeString!String && isOutputRange!(Writer, ubyte))
{
    auto inputRange = NumericStringRange!(ElementType!String)(base64Text);
    return parseBase64(sink, inputRange);
}

pragma(inline, true)
size_t parseBase64Length(const(size_t) chars,
    const(char) padding = Base64MappingChar.padding) @nogc pure
{
    return padding == Base64MappingChar.noPadding
        ? (chars / 4) * 3 + (chars % 4 < 2 ? 0 : (chars % 4 == 2 ? 1 : 2))
        : (chars / 4) * 3;
}

enum ComputingSizeUnit : ubyte
{
    bytes,
    kbytes,
    mbytes,
    gbytes,
    tbytes,
    pbytes,
}

static immutable string[ComputingSizeUnit.max + 1] computingSizeUnitNames = [
    "Bytes",
    "KB",
    "MB",
    "GB",
    "TB",
    "PB",
    ];

enum long computingSizeUnit1K = 1_024L;

static immutable long[ComputingSizeUnit.max + 1] computingSizeUnitValues = [
    1L,
    computingSizeUnit1K,
    computingSizeUnit1K * computingSizeUnit1K,
    computingSizeUnit1K * computingSizeUnit1K * computingSizeUnit1K,
    computingSizeUnit1K * computingSizeUnit1K * computingSizeUnit1K * computingSizeUnit1K,
    computingSizeUnit1K * computingSizeUnit1K * computingSizeUnit1K * computingSizeUnit1K * computingSizeUnit1K,
    ];

static immutable long[ComputingSizeUnit.max + 1] computingSizeUnitMaxs = [
    long.max,
    long.max / computingSizeUnitValues[ComputingSizeUnit.kbytes],
    long.max / computingSizeUnitValues[ComputingSizeUnit.mbytes],
    long.max / computingSizeUnitValues[ComputingSizeUnit.gbytes],
    long.max / computingSizeUnitValues[ComputingSizeUnit.tbytes],
    long.max / computingSizeUnitValues[ComputingSizeUnit.pbytes],
    ];

NumericParsedKind parseComputingSize(scope const(char)[] computingSizeText, const(ComputingSizeUnit) defaultUnit, out long target) pure
{
    return parseComputingSize(computingSizeText, cast(const(const(char)[])[])(computingSizeUnitNames[]), defaultUnit, target);
}

NumericParsedKind parseComputingSize(String)(scope String computingSizeText, scope const(String)[] computingSizeUnitNames, const(ComputingSizeUnit) defaultUnit, out long target) pure
if (isSomeString!String)
{
    target = 0;

    long d;
    int suffixIndex;
    const result = parseIntegralSuffix(computingSizeText, computingSizeUnitNames, d, suffixIndex);

    debug(debug_pham_utl_utl_numeric_parser) debug writeln("result=", result, ", d=", d, ", suffixIndex=", suffixIndex);

    if (result == NumericParsedKind.ok)
    {
        if (d == 0)
            return result;

        const u = suffixIndex < 0 ? defaultUnit : cast(ComputingSizeUnit)suffixIndex;

        debug(debug_pham_utl_utl_numeric_parser) debug writeln("result=", result, ", d=", d, ", u=", u, ", umax=", computingSizeUnitMaxs[u]);

        if (d > 0 && d > computingSizeUnitMaxs[u])
            return NumericParsedKind.overflow;
        if (d < 0 && d < -computingSizeUnitMaxs[u])
            return NumericParsedKind.underflow;

        target = d * computingSizeUnitValues[u];
    }

    return result;
}

NumericParsedKind parseDecimalSuffix(String, Range)(scope ref Range decimalText, scope const(String)[] expectedSuffixNames, out double target, out int suffixIndex) pure
if (isSomeString!String && isNumericLexerRange!Range)
{
    import std.conv : to;
    import std.uni : sicmp;

    alias RangeElement = UElementType!Range;

    target = 0.0;
    suffixIndex = -1;

    auto lexer = NumericLexer!(Range)(decimalText, defaultParseDecimalOptions!RangeElement());
    if (!lexer.hasNumericChar)
        return NumericParsedKind.invalid;

    uint digitsCount;
    RangeElement[50] number;
    while (!lexer.empty && digitsCount < number.length)
    {
        const c = lexer.front;

        if (isDigit(c))
        {
            number[digitsCount++] = c;
            lexer.popFront();
        }
        else if (lexer.allowDecimalChar && lexer.options.isDecimalChar(c))
        {
            number[digitsCount++] = c;
            lexer.popDecimalChar();
        }
        else
            break;
    }
    if (digitsCount == 0)
        return NumericParsedKind.invalid;

    try
    {
        target = number[0..digitsCount].to!double();
    }
    catch (Exception)
    {
        return NumericParsedKind.invalid;
    }

    lexer.skipSpaces();
    if (lexer.empty)
        return NumericParsedKind.ok;

    RangeElement[100] suffix;
    uint suffixLength;
    while (suffixLength < suffix.length && !lexer.empty)
    {
        const c = lexer.front;
        if (lexer.options.isSpaceCharOnly(c))
            break;
        suffix[suffixLength++] = c;
        lexer.popFront();
    }

    lexer.skipSpaceOnlys();
    if (suffixLength == 0 || !lexer.empty)
        return NumericParsedKind.invalid;

    foreach (i, s; expectedSuffixNames)
    {
        if (sicmp(s, suffix[0..suffixLength]) == 0)
        {
            suffixIndex = cast(int)i;
            return NumericParsedKind.ok;
        }
    }

    return NumericParsedKind.invalid;
}

NumericParsedKind parseDecimalSuffix(String)(scope String decimalText, scope const(String)[] expectedSuffixNames, out double target, out int suffixIndex) pure
if (isSomeString!String)
{
    auto range = NumericStringRange!(UElementType!String)(decimalText);
    return parseDecimalSuffix(range, expectedSuffixNames, target, suffixIndex);
}

enum DurationUnit : ubyte
{
    nsecs,
    hnsecs,
    usecs,
    msecs,
    seconds,
    minutes,
    hours,
    days,
    weeks,
}

static immutable string[DurationUnit.max + 1] durationUnitNames = [
    "nsecs",
    "hnsecs",
    "usecs",
    "msecs",
    "seconds",
    "minutes",
    "hours",
    "days",
    "weeks",
    ];

static immutable long[DurationUnit.max + 1] durationUnitMaxs = [
    (Duration.max / 100).total!"nsecs",
    Duration.max.total!"hnsecs",
    Duration.max.total!"usecs",
    Duration.max.total!"msecs",
    Duration.max.total!"seconds",
    Duration.max.total!"minutes",
    Duration.max.total!"hours",
    Duration.max.total!"days",
    Duration.max.total!"weeks",
    ];

NumericParsedKind parseDuration(scope const(char)[] durationText, const(DurationUnit) defaultUnit, out Duration target) pure
{
    return parseDuration(durationText, cast(const(const(char)[])[])(durationUnitNames[]), defaultUnit, target);
}

NumericParsedKind parseDuration(String)(scope String durationText, scope const(String)[] durationUnitNames, const(DurationUnit) defaultUnit, out Duration target) pure
if (isSomeString!String)
{
    target = Duration.zero;

    long d;
    int suffixIndex;
    const result = parseIntegralSuffix(durationText, durationUnitNames, d, suffixIndex);

    debug(debug_pham_utl_utl_numeric_parser) debug writeln("result=", result, ", d=", d, ", suffixIndex=", suffixIndex);

    if (result == NumericParsedKind.ok)
    {
        if (d == 0)
            return result;

        const u = suffixIndex < 0 ? defaultUnit : cast(DurationUnit)suffixIndex;

        debug(debug_pham_utl_utl_numeric_parser) debug writeln("result=", result, ", d=", d, ", u=", u, ", umax=", durationUnitMaxs[u]);

        if (d > 0 && d > durationUnitMaxs[u])
            return NumericParsedKind.overflow;
            
        if (d < 0 && d < -durationUnitMaxs[u])
            return NumericParsedKind.underflow;

        final switch (u) with (DurationUnit)
        {
            case nsecs:
                target = dur!"nsecs"(d);
                break;
            case hnsecs:
                target = dur!"hnsecs"(d);
                break;
            case usecs:
                target = dur!"usecs"(d);
                break;
            case msecs:
                target = dur!"msecs"(d);
                break;
            case seconds:
                target = dur!"seconds"(d);
                break;
            case minutes:
                target = dur!"minutes"(d);
                break;
            case hours:
                target = dur!"hours"(d);
                break;
            case days:
                target = dur!"days"(d);
                break;
            case weeks:
                target = dur!"weeks"(d);
                break;
        }
    }

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
NumericParsedKind parseHexDigits(Range, Target)(scope ref Range hexText, out Target target) pure
if (isNumericLexerRange!Range && isIntegral!Target)
{
    target = 0;

    auto lexer = NumericLexer!Range(hexText, defaultParseHexDigitOptions!(ElementType!Range)());
    if (!lexer.hasNumericChar)
        return NumericParsedKind.invalid;

    uint hexesCount = 0;
    ubyte b;
    while (!lexer.empty)
    {
        if (cvtHexDigit(lexer.front, b))
        {
            if (hexesCount == Target.sizeof*2)
                return NumericParsedKind.overflow;

            target = cast(Target)((target << 4) | b);
            hexesCount++;

            lexer.popFront();
        }
        else if (lexer.conditionSkipSpaces())
        {
            if (lexer.isInvalidAfterContinueSkippingSpaces())
                return NumericParsedKind.invalid;
        }
        else
            return NumericParsedKind.invalid;
    }

    return NumericParsedKind.ok;
}

///dito
NumericParsedKind parseHexDigits(String, Target)(scope String hexText, out Target target) pure
if (isSomeString!String && isIntegral!Target)
{
    auto range = NumericStringRange!(UElementType!String)(hexText);
    return parseHexDigits(range, target);
}

/**
 * Parse 'integralText' to integral value
 * Params:
 *  integralText = character range to be converted
 *  target = integral presentation of integralText
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseIntegral(Range, Target)(scope ref Range integralText, out Target target) pure
if (isNumericLexerRange!Range && isIntegral!Target)
{
    uint digitsCount;
    auto lexer = NumericLexer!Range(integralText, defaultParseIntegralOptions!(UElementType!Range)());
    return parseIntegralImpl(lexer, target, digitsCount);
}

///dito
NumericParsedKind parseIntegral(String, Target)(scope String integralText, out Target target) pure
if (isSomeString!String && isIntegral!Target)
{
    auto range = NumericStringRange!(UElementType!String)(integralText);
    return parseIntegral(range, target);
}

version(none)
NumericParsedKind parseValidIntegral(Target)(scope const(char)[] validIntegralText, ref Target target) pure
in
{
    assert(validIntegralText.length != 0);
}
do
{
    auto isNeg = false;
    auto i = 0;
    if (validIntegralText[0] == '-')
    {
        isNeg = true;
        i++;
    }
    else if (validIntegralText[0] == '+')
        i++;
        
    enum maxDiv10 = Target.max / 10;
    const maxLastDigit = (Target.min < 0 ? 7 : 5) + isNeg;

    static if (Target.sizeof <= int.sizeof)
        int vTemp = 0;
    else
        long vTemp = 0;
        
    ubyte b;
    while (i < validIntegralText.length)
    {
        if (cvtDigit(validIntegralText[i], b))
        {
            if (vTemp >= 0 && (vTemp < maxDiv10 || (vTemp == maxDiv10 && b <= maxLastDigit)))
                vTemp = (vTemp * 10) + b;
            else
                return isNeg ? NumericParsedKind.underflow : NumericParsedKind.overflow;
        }
        else
        {
            if (validIntegralText[i] != '_')
                return NumericParsedKind.invalid;
        }
        i++;
    }
    
    target = isNeg ? cast(Target)(-vTemp) : cast(Target)vTemp;
    return NumericParsedKind.ok;
}

private NumericParsedKind parseIntegralImpl(Lexer, Target)(scope ref Lexer lexer, out Target target, out uint digitsCount) pure
if (isIntegral!Target)
{
    target = 0;
    digitsCount = 0;

    if (!lexer.hasNumericChar)
        return NumericParsedKind.invalid;

    static if (isUnsigned!Target)
    {
        if (lexer.neg)
            return NumericParsedKind.invalid;
    }

    if (lexer.hasHexDigitPrefix)
    {
        ubyte b;
        while (!lexer.empty)
        {
            if (cvtHexDigit(lexer.front, b))
            {
                if (digitsCount == Target.sizeof*2)
                    return lexer.neg ? NumericParsedKind.underflow : NumericParsedKind.overflow;

                target = cast(Target)((target << 4) | b);
                digitsCount++;

                lexer.popFront();
            }
            else if (lexer.conditionSkipSpaces())
            {
                if (lexer.isInvalidAfterContinueSkippingSpaces())
                    return NumericParsedKind.invalid;
            }
            else
                return NumericParsedKind.invalid;
        }
    }
    else
    {
        enum maxDiv10 = Target.max / 10;
        const maxLastDigit = (Target.min < 0 ? 7 : 5) + lexer.neg;

        static if (Target.sizeof <= int.sizeof)
            int vTemp = 0;
        else
            long vTemp = 0;

        NumericParsedKind returnAs(const(NumericParsedKind) r) nothrow @safe
        {
            static if (isSigned!Target)
            {
                if (lexer.neg)
                    vTemp = -vTemp;
            }

            target = cast(Target)vTemp;
            return r;
        }

        ubyte b;
        while (!lexer.empty)
        {
            if (cvtDigit(lexer.front, b))
            {
                if (vTemp >= 0 && (vTemp < maxDiv10 || (vTemp == maxDiv10 && b <= maxLastDigit)))
                {
                    vTemp = (vTemp * 10) + b;
                    digitsCount++;

                    debug(debug_pham_utl_utl_numeric_parser) debug writeln("vTemp=", vTemp, ", b=", b, ", digitsCount=", digitsCount);

                    lexer.popFront();
                }
                else
                    return lexer.neg ? NumericParsedKind.underflow : NumericParsedKind.overflow;
            }
            else if (lexer.conditionSkipSpaces())
            {
                if (lexer.isInvalidAfterContinueSkippingSpaces())
                    return returnAs(NumericParsedKind.invalid);
            }
            else
                return returnAs(NumericParsedKind.invalid);
        }

        return returnAs(NumericParsedKind.ok);
    }

    return NumericParsedKind.ok;
}

NumericParsedKind parseIntegralSuffix(String, Range, Target)(scope ref Range integralText, scope const(String)[] expectedSuffixNames, out Target target, out int suffixIndex) pure
if (isSomeString!String && isNumericLexerRange!Range && isIntegral!Target)
{
    import std.uni : sicmp;

    alias RangeElement = UElementType!Range;

    suffixIndex = -1;
    uint digitsCount;
    auto lexer = NumericLexer!Range(integralText, defaultParseIntegralOptions!(ElementType!Range)());
    auto nk = parseIntegralImpl(lexer, target, digitsCount);

    debug(debug_pham_utl_utl_numeric_parser) debug writeln("nk=", nk, ", target=", target, ", digitsCount=", digitsCount);

    lexer.skipSpaces();
    if (digitsCount == 0 || lexer.empty)
        return nk;

    RangeElement[100] suffix;
    uint suffixLength;
    while (suffixLength < suffix.length && !lexer.empty)
    {
        const c = lexer.front;
        if (lexer.options.isSpaceCharOnly(c))
            break;
        suffix[suffixLength++] = c;
        lexer.popFront();
    }

    lexer.skipSpaceOnlys();
    if (suffixLength == 0 || !lexer.empty)
        return NumericParsedKind.invalid;

    foreach (i, s; expectedSuffixNames)
    {
        if (sicmp(s, suffix[0..suffixLength]) == 0)
        {
            suffixIndex = cast(int)i;
            return NumericParsedKind.ok;
        }
    }

    return NumericParsedKind.invalid;
}

NumericParsedKind parseIntegralSuffix(String, Target)(scope String integralText, scope const(String)[] expectedSuffixNames, out Target target, out int suffixIndex) pure
if (isSomeChar!String && isIntegral!Target)
{
    auto range = NumericStringRange!(UElementType!String)(integralText);
    return parseIntegralSuffix(range, expectedSuffixNames, target, suffixIndex);
}


// Any below codes are private
private:

nothrow @safe unittest // cvtBytesBase64Length
{
    assert(cvtBytesBase64Length(0, false, 0) == 0);
    assert(cvtBytesBase64Length(3, false, 0) == 4);

    assert(cvtBytesBase64Length(4, false, 0, Base64MappingChar.padding) == 8);
    assert(cvtBytesBase64Length(4, false, 0, Base64MappingChar.noPadding) == 6);
}

nothrow @safe unittest // cvtBytesBase64
{
    ubyte[] data = [0x1a, 0x2b, 0x3c, 0x4d, 0x5d, 0x6e];
    assert(cvtBytesBase64(data) == "Gis8TV1u");
}

nothrow @safe unittest // cvtDigit
{
    ubyte b;

    assert(cvtDigit('0', b));
    assert(b == 0);

    assert(cvtDigit('1', b));
    assert(b == 1);

    assert(cvtDigit('9', b));
    assert(b == 9);

    assert(!cvtDigit('a', b));
}

nothrow @safe unittest // cvtDigit2
{
    assert(cvtDigit2('0') == 0);
    assert(cvtDigit2('1') == 1);
    assert(cvtDigit2('9') == 9);
}

nothrow @safe unittest // isDigit
{
    assert(isDigit('0'));
    assert(isDigit('1'));
    assert(isDigit('9'));
    assert(!isDigit('a'));
}

nothrow @safe unittest // cvtHexDigit
{
    ubyte b;

    assert(cvtHexDigit('0', b));
    assert(b == 0);

    assert(cvtHexDigit('9', b));
    assert(b == 9);

    assert(cvtHexDigit('a', b));
    assert(b == 10);

    assert(cvtHexDigit('F', b));
    assert(b == 15);

    assert(!cvtHexDigit('z', b));
}

nothrow @safe unittest // cvtHexDigit2
{
    assert(cvtHexDigit2('0') == 0);
    assert(cvtHexDigit2('9') == 9);
    assert(cvtHexDigit2('a') == 10);
    assert(cvtHexDigit2('F') == 15);
}

nothrow @safe unittest // isHexDigit
{
    assert(isHexDigit('0'));
    assert(isHexDigit('9'));
    assert(isHexDigit('a'));
    assert(isHexDigit('F'));
    assert(!isHexDigit('z'));
}

nothrow @safe unittest // lineBreakCount
{
    assert(lineBreakCount(0, 80) == 0);
    assert(lineBreakCount(1, 80) == 0);
    assert(lineBreakCount(80, 80) == 0);
    assert(lineBreakCount(81, 80) == 1);
    assert(lineBreakCount(160, 80) == 1);
}

nothrow @safe unittest // NumericLexerOptions.isHexDigitPrefix
{
    enum t1 = NumericLexerOptions!char.isHexDigitPrefix("0x0");
    enum t2 = NumericLexerOptions!char.isHexDigitPrefix("0X0");

    assert(!NumericLexerOptions!char.isHexDigitPrefix("x0"));
    assert(!NumericLexerOptions!char.isHexDigitPrefix("0"));
    assert(!NumericLexerOptions!char.isHexDigitPrefix("012"));
}

nothrow @safe unittest // NumericLexer
{
    import std.utf : byCodeUnit;

    NumericLexer!(typeof("".byCodeUnit)) r;

    assert(r.toUpper('A') == 'A');
    assert(r.toUpper('a') == 'A');
    assert(r.toUpper('z') == 'Z');
}

nothrow @safe unittest // parseBase64
{
    import std.conv : to;
    import std.string : representation;
    import pham.utl.utl_array_static : ShortStringBuffer;

    static test(string base64Text, NumericParsedKind expectedCondition, string expectedText,
        uint line = __LINE__)
    {
        ShortStringBuffer!ubyte buffer;
        assert(parseBase64(buffer, base64Text) == expectedCondition, "parseBase64 failed from line#: " ~ line.to!string());
        assert(expectedCondition != NumericParsedKind.ok || buffer[] == expectedText.representation(), "parseBase64 failed from line#: " ~ line.to!string());
    }

    test("QUIx", NumericParsedKind.ok, "AB1");
    test("VGhvdSBzaGFsdCBuZXZlciBjb250aW51ZSBhZnRlciBhc3NlcnRpbmcgbnVsbA==", NumericParsedKind.ok, "Thou shalt never continue after asserting null");
    test("\n  VGhvdSBzaGFsdCBuZXZlciBjb250aW51  \n  ZSBhZnRlciBhc3NlcnRpbmcgbnVsbA==  \n",  NumericParsedKind.ok, "Thou shalt never continue after asserting null");
    test("", NumericParsedKind.invalid, null);
    test(" ??? ", NumericParsedKind.invalid, null);
    test("QUIx?", NumericParsedKind.invalid, null);
    test("VGhvdSBzaGFsdC???", NumericParsedKind.invalid, null);
    test("VGhvdSBzaGFsdCBuZXZlciBjb250aW51ZSBhZnRlciBhc3NlcnRpbmcgbnVsbA==???", NumericParsedKind.invalid, null);
}

nothrow @safe unittest // parseIntegral, parseHexDigits
{
    import std.conv : to;

    int i;
    string s;

    assert(parseIntegral("0", i) == NumericParsedKind.ok);
    assert(i == 0);
    s = "1";
    assert(parseIntegral(s, i) == NumericParsedKind.ok);
    assert(i == 1);
    
    assert(parseIntegral("0123456789", i) == NumericParsedKind.ok);
    assert(i == 123456789);
    s = "12345";
    assert(parseIntegral(s, i) == NumericParsedKind.ok);
    assert(i == 12345);

    assert(parseIntegral("0x01fAc764", i) == NumericParsedKind.ok);
    assert(i == 0x1fAc764);
    assert(parseHexDigits("0x01fAc764", i) == NumericParsedKind.ok);
    assert(i == 0x1fAc764);
    assert(parseHexDigits("01fAc764", i) == NumericParsedKind.ok);
    assert(i == 0x1fAc764);

    assert(parseIntegral("", i) == NumericParsedKind.invalid);
    assert(parseIntegral("0ab", i) == NumericParsedKind.invalid);
    assert(parseIntegral("123 456", i) == NumericParsedKind.invalid);
    assert(parseHexDigits("", i) == NumericParsedKind.invalid);
    assert(parseHexDigits("0x0abxyz", i) == NumericParsedKind.invalid);
    assert(parseHexDigits("0x0 abc", i) == NumericParsedKind.invalid);

    assert(parseIntegral(to!string(long.max), i) == NumericParsedKind.overflow);
    assert(parseIntegral(to!string(long.min), i) == NumericParsedKind.underflow);
    assert(parseIntegral("0x1234567890", i) == NumericParsedKind.overflow);
    assert(parseHexDigits("0x1234567890", i) == NumericParsedKind.overflow);
}

nothrow @safe unittest // parseIntegral
{
    import std.conv : to;
    import std.meta : AliasSeq;
    import std.traits : isSigned, isUnsigned;

    static foreach (I; AliasSeq!(byte, ubyte, short, ushort, int, uint, long, ulong))
    {
        {
            I i1;

            assert(parseIntegral("0", i1) == NumericParsedKind.ok);
            assert(i1 == 0);
            assert(parseIntegral(to!string(I.min), i1) == NumericParsedKind.ok);
            assert(i1 == I.min);
            assert(parseIntegral(to!string(I.max), i1) == NumericParsedKind.ok);
            assert(i1 == I.max);

            static if (isSigned!I)
            {
                assert(parseIntegral("+0", i1) == NumericParsedKind.ok);
                assert(i1 == 0);
                assert(parseIntegral("-0", i1) == NumericParsedKind.ok);
                assert(i1 == 0);
            }
        }

        static if (I.sizeof >= byte.sizeof)
        {{
            I i2;

            assert(parseIntegral("6", i2) == NumericParsedKind.ok);
            assert(i2 == 6);
            assert(parseIntegral("23", i2) == NumericParsedKind.ok);
            assert(i2 == 23);
            assert(parseIntegral("68", i2) == NumericParsedKind.ok);
            assert(i2 == 68);
            assert(parseIntegral("127", i2) == NumericParsedKind.ok);
            assert(i2 == 127);

            static if (isUnsigned!I)
            {
                assert(parseIntegral("255", i2) == NumericParsedKind.ok);
                assert(i2 == 0xFF);
                assert(parseIntegral("0xfF", i2) == NumericParsedKind.ok);
                assert(i2 == 0xFF);
            }

            static if (isSigned!I)
            {
                assert(parseIntegral("+6", i2) == NumericParsedKind.ok);
                assert(i2 == 6);
                assert(parseIntegral("+23", i2) == NumericParsedKind.ok);
                assert(i2 == 23);
                assert(parseIntegral("+68", i2) == NumericParsedKind.ok);
                assert(i2 == 68);
                assert(parseIntegral("+127", i2) == NumericParsedKind.ok);
                assert(i2 == 127);

                assert(parseIntegral("-6", i2) == NumericParsedKind.ok);
                assert(i2 == -6);
                assert(parseIntegral("-23", i2) == NumericParsedKind.ok);
                assert(i2 == -23);
                assert(parseIntegral("-68", i2) == NumericParsedKind.ok);
                assert(i2 == -68);
                assert(parseIntegral("-128", i2) == NumericParsedKind.ok);
                assert(i2 == -128);
            }
        }}

        static if (I.sizeof >= short.sizeof)
        {{
            I i3;

            assert(parseIntegral("468", i3) == NumericParsedKind.ok);
            assert(i3 == 468);
            assert(parseIntegral("32767", i3) == NumericParsedKind.ok);
            assert(i3 == 32767);

            static if (isUnsigned!I)
            {
                assert(parseIntegral("65535", i3) == NumericParsedKind.ok);
                assert(i3 == 0xFFFF);
                assert(parseIntegral("0xFFFF", i3) == NumericParsedKind.ok);
                assert(i3 == 0xFFFF);
            }

            static if (isSigned!I)
            {
                assert(parseIntegral("+468", i3) == NumericParsedKind.ok);
                assert(i3 == 468);
                assert(parseIntegral("+32767", i3) == NumericParsedKind.ok);
                assert(i3 == 32767);

                assert(parseIntegral("-468", i3) == NumericParsedKind.ok);
                assert(i3 == -468);
                assert(parseIntegral("-32768", i3) == NumericParsedKind.ok);
                assert(i3 == -32768);
            }
        }}

        static if (I.sizeof >= int.sizeof)
        {{
            I i4;

            assert(parseIntegral("2147483647", i4) == NumericParsedKind.ok);
            assert(i4 == 2147483647);

            static if (isUnsigned!I)
            {
                assert(parseIntegral("4294967295", i4) == NumericParsedKind.ok);
                assert(i4 == 0xFFFFFFFF);
                assert(parseIntegral("0xFFFFFFFF", i4) == NumericParsedKind.ok);
                assert(i4 == 0xFFFFFFFF);
            }

            static if (isSigned!I)
            {
                assert(parseIntegral("+2147483647", i4) == NumericParsedKind.ok);
                assert(i4 == 2147483647);
                assert(parseIntegral("-2147483648", i4) == NumericParsedKind.ok);
                assert(i4 == -2147483648);
            }
        }}

        static if (I.sizeof >= long.sizeof)
        {{
            I i5;

            assert(parseIntegral("9223372036854775807", i5) == NumericParsedKind.ok);
            assert(i5 == 0x7FFFFFFFFFFFFFFF);
            assert(parseIntegral("0x7FFFFFFFFFFFFFFF", i5) == NumericParsedKind.ok);
            assert(i5 == 0x7FFFFFFFFFFFFFFF);

            static if (isUnsigned!I)
            {
                assert(parseIntegral("18446744073709551615", i5) == NumericParsedKind.ok);
                assert(i5 == 0xFFFFFFFFFFFFFFFF);
                assert(parseIntegral("0xFFFFFFFFFFFFFFFF", i5) == NumericParsedKind.ok);
                assert(i5 == 0xFFFFFFFFFFFFFFFF);
            }

            static if (isSigned!I)
            {
                assert(parseIntegral("+9223372036854775807", i5) == NumericParsedKind.ok);
                assert(i5 == 0x7FFFFFFFFFFFFFFF);
                assert(parseIntegral("-9223372036854775808", i5) == NumericParsedKind.ok);
                assert(i5 == 0x8000000000000000);

                assert(parseIntegral("0x7FFFFFFFFFFFFFFF", i5) == NumericParsedKind.ok);
                assert(i5 == 0x7FFFFFFFFFFFFFFF);
                assert(parseIntegral("0x8000000000000000", i5) == NumericParsedKind.ok);
                assert(i5 == 0x8000000000000000);
            }
        }}
    }
}

unittest // parseDuration
{
    Duration v;

    assert(parseDuration("2 nsecs", DurationUnit.nsecs, v) == NumericParsedKind.ok);
    assert(v == dur!"nsecs"(2));
    assert(parseDuration("2", DurationUnit.nsecs, v) == NumericParsedKind.ok);
    assert(v == dur!"nsecs"(2));

    assert(parseDuration("2 hnsecs", DurationUnit.hnsecs, v) == NumericParsedKind.ok);
    assert(v == dur!"hnsecs"(2), v.toString() ~ " vs " ~ dur!"hnsecs"(2).toString());
    assert(parseDuration("2", DurationUnit.hnsecs, v) == NumericParsedKind.ok);
    assert(v == dur!"hnsecs"(2));

    assert(parseDuration("2 usecs", DurationUnit.usecs, v) == NumericParsedKind.ok);
    assert(v == dur!"usecs"(2));
    assert(parseDuration("2", DurationUnit.usecs, v) == NumericParsedKind.ok);
    assert(v == dur!"usecs"(2));

    assert(parseDuration("2 msecs", DurationUnit.msecs, v) == NumericParsedKind.ok);
    assert(v == dur!"msecs"(2));
    assert(parseDuration("2", DurationUnit.msecs, v) == NumericParsedKind.ok);
    assert(v == dur!"msecs"(2));

    assert(parseDuration("2 seconds", DurationUnit.seconds, v) == NumericParsedKind.ok);
    assert(v == dur!"seconds"(2));
    assert(parseDuration("2", DurationUnit.seconds, v) == NumericParsedKind.ok);
    assert(v == dur!"seconds"(2));

    assert(parseDuration("2 minutes", DurationUnit.minutes, v) == NumericParsedKind.ok);
    assert(v == dur!"minutes"(2));
    assert(parseDuration("2", DurationUnit.minutes, v) == NumericParsedKind.ok);
    assert(v == dur!"minutes"(2));

    assert(parseDuration("2 hours", DurationUnit.hours, v) == NumericParsedKind.ok);
    assert(v == dur!"hours"(2));
    assert(parseDuration("2", DurationUnit.hours, v) == NumericParsedKind.ok);
    assert(v == dur!"hours"(2));

    assert(parseDuration("2 days", DurationUnit.days, v) == NumericParsedKind.ok);
    assert(v == dur!"days"(2));
    assert(parseDuration("2", DurationUnit.days, v) == NumericParsedKind.ok);
    assert(v == dur!"days"(2));

    assert(parseDuration("2 weeks", DurationUnit.weeks, v) == NumericParsedKind.ok);
    assert(v == dur!"weeks"(2));
    assert(parseDuration("2", DurationUnit.weeks, v) == NumericParsedKind.ok);
    assert(v == dur!"weeks"(2));

    assert(parseDuration("minutes", DurationUnit.minutes, v) == NumericParsedKind.invalid);
    assert(parseDuration("2 minutes?", DurationUnit.minutes, v) == NumericParsedKind.invalid);
    assert(parseDuration("9223372036854775807 minutes", DurationUnit.minutes, v) == NumericParsedKind.overflow);
    assert(parseDuration("-9223372036854775807 minutes", DurationUnit.minutes, v) == NumericParsedKind.underflow);
}

unittest // parseComputingSize
{
    long v;

    assert(parseComputingSize("2Bytes", ComputingSizeUnit.bytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.bytes] * 2);
    assert(parseComputingSize("2", ComputingSizeUnit.bytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.bytes] * 2);

    assert(parseComputingSize("2 KB", ComputingSizeUnit.kbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.kbytes] * 2);
    assert(parseComputingSize("2", ComputingSizeUnit.kbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.kbytes] * 2);

    assert(parseComputingSize("2 mb", ComputingSizeUnit.mbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.mbytes] * 2);
    assert(parseComputingSize("2", ComputingSizeUnit.mbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.mbytes] * 2);

    assert(parseComputingSize("2  Gb", ComputingSizeUnit.gbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.gbytes] * 2);
    assert(parseComputingSize("2", ComputingSizeUnit.gbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.gbytes] * 2);

    assert(parseComputingSize("2 TB", ComputingSizeUnit.tbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.tbytes] * 2);
    assert(parseComputingSize("2", ComputingSizeUnit.tbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.tbytes] * 2);

    assert(parseComputingSize("2PB", ComputingSizeUnit.pbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.pbytes] * 2);
    assert(parseComputingSize("2", ComputingSizeUnit.pbytes, v) == NumericParsedKind.ok);
    assert(v == computingSizeUnitValues[ComputingSizeUnit.pbytes] * 2);
}

version(none)
unittest // parseValidIntegral
{
    int v;
    auto a = parseValidIntegral!int("123", v);
    assert(a == NumericParsedKind.ok);
    assert(v == 123);
    
    a = parseValidIntegral!int("+123", v);
    assert(a == NumericParsedKind.ok);
    assert(v == 123);
    
    a = parseValidIntegral!int("-123", v);
    assert(a == NumericParsedKind.ok);
    assert(v == -123);
    
    a = parseValidIntegral!int("+123__456", v);
    assert(a == NumericParsedKind.ok);
    assert(v == 123_456);
    
    a = parseValidIntegral!int("-123_456", v);
    assert(a == NumericParsedKind.ok);
    assert(v == -123_456);    
}
