/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_convert;

public import std.ascii : LetterCase;
import std.traits : fullyQualifiedName, isIntegral;

/**
 * Converts string of base-64 characters into ubyte array
 * Params:
 *   validBase64Text = base-64 characters to be converted
 * Returns:
 *   ubyte[] if `validBase64Text` is a valid base-64 characters
 *   null/empty if `validBase64Text` is invalid
 */
ubyte[] bytesFromBase64s(scope const(char)[] validBase64Text) nothrow pure @safe
{
    import pham.utl.utl_array_append : Appender;
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseBase64;
    import pham.utl.utl_utf8 : NoDecodeInputRange;

    if (validBase64Text.length == 0)
        return null;

    NoDecodeInputRange!(validBase64Text, char) inputRange;
    Appender!(ubyte[]) result;
    result.reserve((validBase64Text.length / 4) * 3);
    if (parseBase64(result, inputRange) != NumericParsedKind.ok)
        return null;
    return result[];
}

/**
 * Convert byte array to its base64 presentation
 * Params:
 *  bytes = bytes to be converted
 * Returns:
 *  array of base64 characters
 */
char[] bytesToBase64s(scope const(ubyte)[] bytes) nothrow pure @safe
{
    import pham.utl.utl_numeric_parser : Base64MappingChar, NumericParsedKind, cvtBytesBase64;

    if (bytes.length == 0)
        return null;

    return cvtBytesBase64(bytes, Base64MappingChar.padding);
}

/**
 * Converts string of hex-digits into ubyte array
 * Params:
 *   validHexDigits = hex-digits to be converted
 * Returns:
 *   ubyte[] if `validHexDigits` is a valid hex-digits
 *   null/empty if `validHexDigits` is invalid
 */
ubyte[] bytesFromHexs(scope const(char)[] validHexDigits) nothrow pure @safe
{
    import pham.utl.utl_array_append : Appender;
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseBase16;
    import pham.utl.utl_utf8 : NoDecodeInputRange;

    if (validHexDigits.length == 0)
        return null;

    NoDecodeInputRange!(validHexDigits, char) inputRange;
    Appender!(ubyte[]) result;
    result.reserve(validHexDigits.length / 2);
    if (parseBase16(result, inputRange) != NumericParsedKind.ok)
        return null;
    return result[];
}

/**
 * Convert byte array to its hex presentation
 * Params:
 *  bytes = bytes to be converted
 * Returns:
 *  array of hex characters
 */
char[] bytesToHexs(scope const(ubyte)[] bytes) nothrow pure @safe
{
    import pham.utl.utl_numeric_parser : cvtBytesBase16;

    if (bytes.length == 0)
        return null;

    return cvtBytesBase16(bytes, LetterCase.upper);
}

/**
 * Converts an integral value into character output-range and returns its' output-range
 * Params:
 *   sink = character output-range
 *   n = an integral value to be converted
 *   paddingSize = optional padding length
 *   paddingChar = optional padding character; used only if paddingSize is not zero
 *   letterCase = specified upper-case or lower-case characters for radix 16 conversion
 * Returns:
 *   passed in paramter `sink`
 */
ref Writer putNumber(uint radix = 10, N, Writer)(return ref Writer sink, N n,
    const(ubyte) paddingSize = 0, const(char) paddingChar = '0',
    const(LetterCase) letterCase = LetterCase.upper) nothrow pure @safe
if (isIntegral!N && (radix == 2 || radix == 8 || radix == 10 || radix == 16))
{
    import std.ascii : lowerHexDigits, upperHexDigits=hexDigits, decimalDigits=digits;
    import std.range.primitives : put;
    import std.traits : Unqual, isUnsigned;

    alias UN = Unqual!N;
    enum bufSize = N.sizeof * 8;

    char[bufSize] bufDigits;
    size_t bufIndex = bufSize;

    static if (isUnsigned!N || radix != 10)
        const isNeg = false;
    else
        const isNeg = n < 0;

    static if (radix == 10)
    {
        UN un = isNeg ? cast(N)-n : n;
        while (un >= 10)
        {
            bufDigits[--bufIndex] = decimalDigits[cast(ubyte)(un % 10)];
            un /= 10;
        }
        bufDigits[--bufIndex] = decimalDigits[cast(ubyte)un];
    }
    else
    {
        static if (radix == 2)
        {
            enum mask = 0x1;
            enum shift = 1;
        }
        else static if (radix == 8)
        {
            enum mask = 0x7;
            enum shift = 3;
        }
        else static if (radix == 16)
        {
            enum mask = 0xf;
            enum shift = 4;
        }
        else
            static assert(0);

        const radixDigits = letterCase == LetterCase.upper ? upperHexDigits : lowerHexDigits;
        UN un = n;
        do
        {
            bufDigits[--bufIndex] = radixDigits[un & mask];
        }
        while (un >>>= shift);
    }

    if (isNeg)
        put(sink, '-');

    if (paddingSize)
    {
        size_t cn = isNeg ? (bufSize - bufIndex + 1) : (bufSize - bufIndex);
        while (cn < paddingSize)
        {
            put(sink, paddingChar);
            cn++;
        }
    }

    put(sink, bufDigits[bufIndex..bufSize]);
    return sink;
}

deprecated("please use " ~ fullyQualifiedName!putNumber)
alias toString = putNumber;


// Any below codes are private
private:

nothrow @safe unittest // bytesFromHexs & bytesToHexs
{
    assert(bytesToHexs([0]) == "00");
    assert(bytesToHexs([1]) == "01");
    assert(bytesToHexs([15]) == "0F");
    assert(bytesToHexs([255]) == "FF");

    ubyte[] r;
    r = bytesFromHexs("00");
    assert(r == [0]);
    r = bytesFromHexs("01");
    assert(r == [1]);
    r = bytesFromHexs("0F");
    assert(r == [15]);
    r = bytesFromHexs("FF");
    assert(r == [255]);
    r = bytesFromHexs("FFXY");
    assert(r == []);

    static immutable testHexs = "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443";
    auto bytes = bytesFromHexs(testHexs);
    assert(bytesToHexs(bytes) == testHexs);
}

nothrow @safe unittest // bytesFromBase64s
{
    import std.string : representation;

    assert(bytesFromBase64s("QUIx") == "AB1".representation());
}

@safe unittest // putNumber
{
    import std.conv : to;
    import pham.utl.utl_array_append : Appender;

    void testCheck(uint radix = 10, N)(N n, const(ubyte) pad, string expected,
        uint line = __LINE__)
    {
        auto buffer = Appender!string(64);
        putNumber!radix(buffer, n, pad);
        assert(buffer.data == expected, line.to!string() ~ ": " ~ buffer.data ~ " vs " ~ expected);
    }

    testCheck(0, 0, "0");
    testCheck(0, 3, "000");

    testCheck(1, 0, "1");
    testCheck(1, 2, "01");

    testCheck(-1, 0, "-1");
    testCheck(-1, 4, "-001");

    testCheck(1_000_000, 0, "1000000");
    testCheck(1_000_000, 9, "001000000");
    testCheck(-8_000_000, 0, "-8000000");
    testCheck(-8_000_000, 9, "-08000000");

    testCheck!2(2U, 0, "10");
    testCheck!2(2U, 4, "0010");
    testCheck!2(cast(int)-456, 32, "11111111111111111111111000111000");

    testCheck!16(255U, 0, "FF");
    testCheck!16(255U, 4, "00FF");
    testCheck!16(cast(int)-456, 8, "FFFFFE38");

    // Test default call
    auto buffer = Appender!string(10);
    assert(putNumber(buffer, 10).data == "10");
}
