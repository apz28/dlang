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

public import std.ascii : LetterCase;
import std.range.primitives : ElementEncodingType, ElementType, empty, front, popFront, put,
    isInfinite, isInputRange, isOutputRange;
import std.traits : isIntegral, isSigned, isSomeChar, isUnsigned, Unqual;

import pham.utl.utl_utf8;

nothrow @safe:

enum Base64MappingChar : char
{
    map62th = '+',
    map63th = '/',
    padding = '=',
    noPadding = '\0',    
}

size_t cvtBytesBase64Length(const(size_t) bytesLength,
    const(char) padding = Base64MappingChar.padding) @nogc pure
{
    const mod3 = bytesLength % 3;
    if (padding == Base64MappingChar.noPadding)
        return (bytesLength / 3) * 4 + (mod3 == 0 ? 0 : (mod3 == 1 ? 2 : 3));
    else
        return (bytesLength / 3 + (mod3 ? 1 : 0)) * 4;
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
char[] cvtBytesBase64(scope const(ubyte)[] bytes,
    const(char) padding = Base64MappingChar.padding,
    const(bool) isLineBreak = false) pure @trusted
{
    if (bytes.length == 0)
        return null;

    enum lineBreakChar = '\n';
    enum lineBreakLength = 80;
    
    static immutable encodeMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        ~ Base64MappingChar.map62th ~ Base64MappingChar.map63th;

    const size_t resultLength = cvtBytesBase64Length(bytes.length, padding)
        + (isLineBreak ? lineBreakCount(bytes.length, lineBreakLength) : 0);
        
    size_t resultLineBreak = 0;
    char[] result = new char[resultLength];    
    auto resultPtr = &result[0];
    auto bytesPtr = &bytes[0];
    
    const blocks = bytes.length / 3;
    foreach (_; 0..blocks)
    {
        if (isLineBreak && resultLineBreak >= lineBreakLength)
        {
            resultLineBreak = 0;
            *resultPtr++ = lineBreakChar;        
        }
        
        const val = (bytesPtr[0] << 16) | (bytesPtr[1] << 8) | bytesPtr[2];
        *resultPtr++ = encodeMap[val >> 18       ];
        *resultPtr++ = encodeMap[val >> 12 & 0x3f];
        *resultPtr++ = encodeMap[val >>  6 & 0x3f];
        *resultPtr++ = encodeMap[val       & 0x3f];
        bytesPtr += 3;
        
        if (isLineBreak)
            resultLineBreak += 4;           
    }
    
    const remain = bytes.length % 3;
    if (remain)
    {
        const val = (bytesPtr[0] << 16) | (remain == 2 ? bytesPtr[1] << 8 : 0);
        *resultPtr++ = encodeMap[val >> 18       ];
        *resultPtr++ = encodeMap[val >> 12 & 0x3f];

        final switch (remain)
        {
            case 2:
                *resultPtr++ = encodeMap[val >> 6 & 0x3f];
                if (padding != Base64MappingChar.noPadding)
                    *resultPtr++ = padding;
                break;
            case 1:
                if (padding != Base64MappingChar.noPadding)
                {
                    *resultPtr++ = padding;
                    *resultPtr++ = padding;
                }
                break;
        }
    }
    
    return result;
}

/**
 * Convert byte array to its hex presentation
 * Params:
 *  bytes = bytes to be converted
 *  letterCase = use upper or lower case letters
 *  isLineBreak = should adding '\n' for each 80 hex characters?
 * Returns:
 *  array of hex characters
 */
char[] cvtBytesHex(scope const(ubyte)[] bytes,
    const(LetterCase) letterCase = LetterCase.upper,
    const(bool) isLineBreak = false) pure @trusted
{
    import std.ascii : lowerHexDigits, upperHexDigits=hexDigits;

    if (bytes.length == 0)
        return null;

    enum lineBreakChar = '\n';
    enum lineBreakLength = 80;

    const hexDigits = letterCase == LetterCase.upper ? upperHexDigits : lowerHexDigits;
    
    const size_t resultLength = bytes.length * 2
        + (isLineBreak ? lineBreakCount(bytes.length, lineBreakLength) : 0);
    
    size_t resultLineBreak = 0;
    char[] result = new char[resultLength];    
    auto resultPtr = &result[0];
    
    foreach (b; bytes)
    {        
        if (isLineBreak && resultLineBreak >= lineBreakLength)
        {
            resultLineBreak = 0;
            *resultPtr++ = lineBreakChar;
        }        
        
        *resultPtr++ = hexDigits[(b >> 4) & 0xF];
        *resultPtr++ = hexDigits[b & 0xF];
        
        if (isLineBreak)
            resultLineBreak += 2;
    }
    
    return result;
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
size_t lineBreakCount(const(size_t) charsLength, const(size_t) breakLength) @nogc pure
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
nothrow @safe:

    /// Skip these characters, set to null to if not used
    Unqual!Char[] groupSeparators = ['_'];
    NumericLexerFlag flags = NumericLexerFlag.skipLeadingBlank | NumericLexerFlag.skipTrailingBlank;
    Unqual!Char decimalChar = '.';

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

enum isConstCharArray(T) =
    (is(immutable(T) == immutable(C)[], C) && (is(C == char) || is(C == wchar) || is(C == dchar)))
    || (is(const(T) == const(C)[], C) && (is(C == char) || is(C == wchar) || is(C == dchar)));

enum isNumericLexerRange(Range) = isInputRange!Range && isSomeChar!(ElementType!Range) && !isInfinite!Range;

struct Base64Lexer(Range, char map62th = Base64MappingChar.map62th, char map63th = Base64MappingChar.map63th)
if (isNumericLexerRange!Range)
{
nothrow @safe:

public:
    alias RangeElement = Unqual!(ElementType!Range);

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

    size_t conditionSkipSpaces() pure
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
        scope (failure) assert(0, "Assume nothrow failed");

        value.popFront();
        _count++;

        while (!value.empty && options.isGroupSeparator(value.front))
        {
            value.popFront();
            _count++;
        }
    }

    size_t skipPaddingChars() pure
    {
        size_t result;
        while (!empty && front == Base64MappingChar.padding)
        {
            result++;
            popFront();
        }
        return result;
    }

    size_t skipSpaces() pure
    {
        size_t result;
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

    @property bool empty() const @nogc pure
    {
        return value.empty;
    }

    @property RangeElement front() const pure
    in
    {
        assert(!empty);
    }
    do
    {
        scope (failure) assert(0, "Assume nothrow failed");

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
        scope (failure) assert(0, "Assume nothrow failed");

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
    alias RangeElement = Unqual!(ElementType!Range);

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

    size_t conditionSkipSpaces() pure
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
        scope (failure) assert(0, "Assume nothrow failed");

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

    size_t skipSpaces() pure
    {
        size_t result;
        while (!empty && options.isSpaceChar(front))
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

    @property bool empty() const @nogc pure
    {
        return value.empty && !_hasSavedFront;
    }

    @property RangeElement front() const pure
    in
    {
        assert(!empty);
    }
    do
    {
        scope (failure) assert(0, "Assume nothrow failed");

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
        scope (failure) assert(0, "Assume nothrow failed");

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

struct NumericStringRange(S)
if (isConstCharArray!S)
{
@nogc nothrow pure @safe:

public:
    alias RangeElement = Unqual!(ElementEncodingType!S);

public:
    this(S str) scope
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
        typeof(this) result = this;
        return result;
    }

    pragma(inline, true)
    @property RangeElement back() const scope
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
    @property RangeElement front() const scope
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
    size_t _i, _length;
    S _str;
}

enum NumericParsedKind : ubyte
{
    ok,
    invalid,
    overflow,
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
 * Parse 'base64Text' to ubyte[] sink
 * Params:
 *  base64Text = character range to be converted
 *  sink = sink to hold ubytes
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseBase64(Range, Writer)(scope ref Range base64Text, ref Writer sink) pure
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
NumericParsedKind parseBase64(S, Writer)(scope S base64Text, ref Writer sink) pure
if (isConstCharArray!S && isOutputRange!(Writer, ubyte))
{
    auto range = NumericStringRange!S(base64Text);
    return parseBase64(range, sink);
}

/**
 * Parse 'hexText' to integral value
 * Params:
 *  hexText = character range to be converted
 *  v = integral presentation of hexText
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseHexDigits(Range, Target)(scope ref Range hexText, out Target v) pure
if (isNumericLexerRange!Range && isIntegral!Target)
{
    v = 0;

    auto lexer = NumericLexer!Range(hexText, defaultParseHexDigitOptions!(ElementType!Range)());
    if (!lexer.hasNumericChar)
        return NumericParsedKind.invalid;

    size_t count;
    ubyte b;
    while (!lexer.empty)
    {
        if (cvtHexDigit(lexer.front, b))
        {
            if (count == Target.sizeof*2)
                return NumericParsedKind.overflow;

            v = cast(Target)((v << 4) | b);
            count++;

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
NumericParsedKind parseHexDigits(S, Target)(scope S hexText, out Target v) pure
if (isConstCharArray!S && isIntegral!Target)
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
NumericParsedKind parseHexDigits(Range, Writer)(scope ref Range hexDigitText, ref Writer sink) pure
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
NumericParsedKind parseHexDigits(S, Writer)(scope S hexDigitText, ref Writer sink) pure
if (isConstCharArray!S && isOutputRange!(Writer, ubyte))
{
    auto range = NumericStringRange!S(hexDigitText);
    return parseHexDigits(range, sink);
}

/**
 * Parse 'integralText' to integral value
 * Params:
 *  integralText = character range to be converted
 *  v = integral presentation of integralText
 * Returns:
 *  NumericParsedKind
 */
NumericParsedKind parseIntegral(Range, Target)(scope ref Range integralText, out Target v) pure
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
        size_t count;
        ubyte b;
        while (!lexer.empty)
        {
            if (cvtHexDigit(lexer.front, b))
            {
                if (count == Target.sizeof*2)
                    return NumericParsedKind.overflow;

                v = cast(Target)((v << 4) | b);
                count++;

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
        const maxLastDigit = (Target.min < 0 ? 7 : 5) + lexer.neg;

        static if (Target.sizeof <= int.sizeof)
            int vTemp = 0;
        else
            long vTemp = 0;

        ubyte b;
        while (!lexer.empty)
        {
            if (cvtDigit(lexer.front, b))
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
            else if (lexer.conditionSkipSpaces())
            {
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
NumericParsedKind parseIntegral(S, Target)(scope S integralText, out Target v) pure
if (isConstCharArray!S && isIntegral!Target)
{
    auto range = NumericStringRange!S(integralText);
    return parseIntegral(range, v);
}


// Any below codes are private
private:

nothrow @safe unittest // cvtBytesBase64Length
{
    assert(cvtBytesBase64Length(0) == 0);
    assert(cvtBytesBase64Length(3) == 4);

    assert(cvtBytesBase64Length(4, Base64MappingChar.padding) == 8);
    assert(cvtBytesBase64Length(4, Base64MappingChar.noPadding) == 6);    
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
    import pham.utl.utl_array : ShortStringBuffer;

    static test(string base64Text, NumericParsedKind expectedCondition, string expectedText,
        uint line = __LINE__)
    {
        ShortStringBuffer!ubyte buffer;
        assert(parseBase64(base64Text, buffer) == expectedCondition, "parseBase64 failed from line#: " ~ to!string(line));
        assert(expectedCondition != NumericParsedKind.ok || buffer[] == expectedText.representation(), "parseBase64 failed from line#: " ~ to!string(line));
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
