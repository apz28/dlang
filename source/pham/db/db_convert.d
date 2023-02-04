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

module pham.db.convert;

import core.time : convert, dur;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.math : abs, pow;
import std.system : Endian;
import std.traits: isIntegral, isSomeChar, isUnsigned, Unqual;
import std.utf : isValidCodepoint;

version (unittest) import pham.utl.test;
import pham.dtm.tick : Tick;
import pham.utl.object : limitRangeValue;
import pham.db.type;

nothrow @safe:

/**
 * Checks and returns `value` within `min` and `max` inclusive
 * Params:
 *   value = a value to be checked
 *   min = inclusive minimum value
 *   max = inclusive maximum value
 * Returns:
 *   `min` if `value` is less than `min`
 *   `max` if `value` is greater than `max`
 *   otherwise `value`
 */
pragma(inline, true)
Duration limitRangeTimeout(Duration value,
    Duration min = minTimeoutDuration, Duration max = maxTimeoutDuration) @nogc pure
{
    return limitRangeValue(value, min, max);
}

/**
 * Checks and returns `value` within `min` and `max` inclusive as millisecond unit
 * Params:
 *   value = a value to be checked
 *   min = inclusive minimum value
 *   max = inclusive maximum value
 * Returns:
 *   `min` if `value` is less than `min`
 *   `max` if `value` is greater than `max`
 *   otherwise `value`
 */
pragma(inline, true)
int32 limitRangeTimeoutAsMilliSecond(scope const(Duration) value,
    scope const(Duration) min = minTimeoutDuration, scope const(Duration) max = maxTimeoutDuration) @nogc pure
{
    return cast(int32)limitRangeValue(value.total!"msecs", min.total!"msecs"(), max.total!"msecs"());
}

/**
 * Checks and returns `value` within `min` and `max` inclusive as second unit
 * Params:
 *   value = a value to be checked
 *   min = inclusive minimum value
 *   max = inclusive maximum value
 * Returns:
 *   `min` if `value` is less than `min`
 *   `max` if `value` is greater than `max`
 *   otherwise `value`
 */
pragma(inline, true)
int32 limitRangeTimeoutAsSecond(scope const(Duration) value,
    scope const(Duration) min = minTimeoutDuration, scope const(Duration) max = maxTimeoutDuration) @nogc pure
{
    return cast(int32)limitRangeValue(value.total!"seconds", min.total!"seconds"(), max.total!"seconds"());
}

/**
 * Removes date part from a hecto-nanoseconds
 * Params:
 *   hnsecs = a hecto-nanoseconds
 * Returns:
 *   a hecto-nanoseconds date part units to be removed
 */
int64 removeDateUnitFromHNSecs(const(int64) hnsecs) @nogc pure
{
    const hnsecsAsDays = convert!("hnsecs", "days")(hnsecs);
    const result = hnsecs - convert!("days", "hnsecs")(hnsecsAsDays);
    return result < 0 ? result + hnsecsPerDay : result;
}

/**
 * Removes time part from a hecto-nanoseconds
 * Params:
 *   hnsecs = a hecto-nanoseconds
 * Returns:
 *   a hecto-nanoseconds time part units to be removed
 */
int64 removeTimeUnitFromHNSecs(const(int64) hnsecs) @nogc pure
{
    const hnsecsAsDays = convert!("hnsecs", "days")(hnsecs);
    return convert!("days", "hnsecs")(hnsecsAsDays);
}

/**
 * Safely converts a string/array of digits, `validSecondStr`, to Duration type value
 * Params:
 *   validSecondStr = a string/array of digits to be converted
 *   failedValue = returns this value if `validSecondStr` is not a valid digits
 *   emptyValue = returns this value if `validSecondStr` is empty (length = 0)
 * Returns:
 *   a Duration value represented by `validSecondStr`
 */
Duration secondDigitsToDurationSafe(scope const(char)[] validSecondStr, Duration failedValue,
    Duration emptyValue = Duration.zero) pure
{
    // Special try construct for grep
    try {
        return validSecondStr.length == 0 ? emptyValue : dur!"seconds"(to!int64(validSecondStr));
    } catch (Exception) return failedValue;
}

/**
 * Safely converts a string/array of digits, `validDecimalStr`, to a Decimal type value
 * Params:
 *   validDecimalStr = a string/array of digits to be converted
 *   failedValue = returns this value if `validDecimalStr` is not a valid digits
 *   emptyValue = returns this value if `validDecimalStr` is empty (length = 0)
 * Returns:
 *   a Decimal value represented by `validDecimalStr`
 */
D toDecimalSafe(D)(scope const(char)[] validDecimalStr, D failedValue,
    D emptyValue = D.zero)
if (isDecimal!D)
{
    // Special try construct for grep
    try {
        return validDecimalStr.length == 0 ? emptyValue : D(validDecimalStr);
    } catch (Exception) return failedValue;
}

/**
 * Safely converts a string/array of digits, `validIntegerStr`, to an integer type value
 * Params:
 *   validIntegerStr = a string/array of digits to be converted
 *   failedValue = returns this value if `validIntegerStr` is not a valid digits
 *   emptyValue = returns this value if `validIntegerStr` is empty (length = 0)
 * Returns:
 *   an integer value represented by `validIntegerStr`
 */
I toIntegerSafe(I)(scope const(char)[] validIntegerStr, const(I) failedValue,
    const(I) emptyValue = 0) pure
if (is(I == int) || is(I == uint)
    || is(I == long) || is(I == ulong)
    || is(I == short) || is(I == ushort))
{
    // Special try construct for grep
    try {
        return validIntegerStr.length == 0 ? emptyValue : to!I(validIntegerStr);
    } catch (Exception) return failedValue;
}

enum failedConvertedString = "?";

/**
 * Convert a valid character, `validChar`, to string
 * Params:
 *   validChar = a valid character to be converted
 *   failedValue = a returned value if `validChar` is not valid
 * Returns:
 *   string represents `validChar`
 *   empty string if `validChar` is null terminated character ('\0')
 */
string toStringSafe(C)(C validChar, string failedValue) pure
if (isSomeChar!C)
{
    // Special try construct for grep
    try {
        return validChar == 0
            ? null
            : (isValidCodepoint!C(validChar) ? to!string(validChar) : failedValue);
    } catch (Exception) return failedValue;
}

/**
 * Convert a valid wide string, `validWideString`, to string
 * Params:
 *   validWideString = a valid wide string to be converted
 *   failedValue = a returned value if `validWideString` is not valid
 * Returns:
 *   string represents `validWideString`
 */
string toStringSafe(S)(S validWideString, string failedValue) pure
if (is(S == wstring) || is(S == dstring))
{
    // Special try construct for grep
    try {
        return validWideString.length == 0 ? null : to!string(validWideString);
    } catch (Exception) return failedValue;
}

string toStringSafe(I)(I number) pure
if (isIntegral!I)
{
    scope (failure) assert(0);
    
    return to!string(number);    
}

/**
 * Convert an array of ubytes, `v`, into a native unsigned integer value for template type `EndianKind`
 * Params:
 *   v = an array of ubyte to be converted
 * Returns:
 *   native unsigned integer represented the value, `v`
 */
pragma(inline, true)
T uintDecode(T, Endian EndianKind)(scope const(ubyte)[] v) @nogc pure
if (isUnsigned!T && T.sizeof > 1)
in
{
    assert(v.length >= T.sizeof);
}
do
{
    T result = void;

    static if (T.sizeof == 4)
    {
        static if (EndianKind == Endian.littleEndian)
            result = v[0]
                | (cast(T)v[1] << 8)
                | (cast(T)v[2] << 16)
                | (cast(T)v[3] << 24);
        else
            result = (cast(T)v[0] << 24)
                | (cast(T)v[1] << 16)
                | (cast(T)v[2] << 8)
                | v[3];
    }
    else static if (T.sizeof == 8)
    {
        static if (EndianKind == Endian.littleEndian)
            result = v[0]
                | (cast(T)v[1] << 8)
                | (cast(T)v[2] << 16)
                | (cast(T)v[3] << 24)
                | (cast(T)v[4] << 32)
                | (cast(T)v[5] << 40)
                | (cast(T)v[6] << 48)
                | (cast(T)v[7] << 56);
        else
            result = (cast(T)v[0] << 56)
                | (cast(T)v[1] << 48)
                | (cast(T)v[2] << 40)
                | (cast(T)v[3] << 32)
                | (cast(T)v[4] << 24)
                | (cast(T)v[5] << 16)
                | (cast(T)v[6] << 8)
                | v[7];
    }
    else static if (T.sizeof == 2)
    {
        static if (EndianKind == Endian.littleEndian)
            result = v[0]
                | (cast(T)v[1] << 8);
        else
            result = (cast(T)v[0] << 8)
                | v[1];
    }
    else
    {
        static assert(0, "Unsupport " ~ T.stringof);
    }

    version (BigEndian)
    static if (EndianKind == Endian.littleEndian)
        result = swapEndian(result);

    return result;
}

/**
 * Convert a native unsigned integer value, `v`, into an array of ubytes for template type `EndianKind`
 * Params:
 *   v = an unsigned integer to be converted
 * Returns:
 *   static array of ubytes represented the value, `v`
 */
pragma(inline, true)
ubyte[T.sizeof] uintEncode(T, Endian EndianKind)(T v) @nogc pure
if (isUnsigned!T && T.sizeof > 1)
{
    ubyte[T.sizeof] result = void;
    Unqual!T uv = v;

    version (BigEndian)
    static if (EndianKind == Endian.littleEndian)
        uv = swapEndian(uv);

    static if (T.sizeof == 4)
    {
        static if (EndianKind == Endian.littleEndian)
        {
            result[0] = uv & 0xFF;
            result[1] = (uv >> 8) & 0xFF;
            result[2] = (uv >> 16) & 0xFF;
            result[3] = (uv >> 24) & 0xFF;
        }
        else
        {
            result[0] = (uv >> 24) & 0xFF;
            result[1] = (uv >> 16) & 0xFF;
            result[2] = (uv >> 8) & 0xFF;
            result[3] = uv & 0xFF;
        }
    }
    else static if (T.sizeof == 8)
    {
        static if (EndianKind == Endian.littleEndian)
        {
            result[0] = uv & 0xFF;
            result[1] = (uv >> 8) & 0xFF;
            result[2] = (uv >> 16) & 0xFF;
            result[3] = (uv >> 24) & 0xFF;
            result[4] = (uv >> 32) & 0xFF;
            result[5] = (uv >> 40) & 0xFF;
            result[6] = (uv >> 48) & 0xFF;
            result[7] = (uv >> 56) & 0xFF;
        }
        else
        {
            result[0] = (uv >> 56) & 0xFF;
            result[1] = (uv >> 48) & 0xFF;
            result[2] = (uv >> 40) & 0xFF;
            result[3] = (uv >> 32) & 0xFF;
            result[4] = (uv >> 24) & 0xFF;
            result[5] = (uv >> 16) & 0xFF;
            result[6] = (uv >> 8) & 0xFF;
            result[7] = uv & 0xFF;
        }
    }
    else static if (T.sizeof == 2)
    {
        static if (EndianKind == Endian.littleEndian)
        {
            result[0] = uv & 0xFF;
            result[1] = (uv >> 8) & 0xFF;
        }
        else
        {
            result[0] = (uv >> 8) & 0xFF;
            result[1] = uv & 0xFF;
        }
    }
    else
    {
        static assert(0, "Unsupport " ~ T.stringof);
    }

    return result;
}


// Any below codes are private
private:

unittest // limitRangeTimeout
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.limitRangeTimeout");

    assert(limitRangeTimeout(dur!"seconds"(-1)) == minTimeoutDuration);
    assert(limitRangeTimeout(dur!"seconds"(1)) == dur!"seconds"(1));
    assert(limitRangeTimeout(Duration.max) == maxTimeoutDuration);
}

unittest // limitRangeTimeoutAsSecond
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.limitRangeTimeoutAsSecond");

    assert(limitRangeTimeoutAsSecond(dur!"seconds"(-1)) == minTimeoutDuration.total!"seconds"());
    assert(limitRangeTimeoutAsSecond(dur!"seconds"(1)) == 1);
    assert(limitRangeTimeoutAsSecond(Duration.max) == maxTimeoutDuration.total!"seconds"());
}

unittest // removeDateUnitFromHNSecs
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.removeDateUnitFromHNSecs");

    const t = dur!"hours"(1) + dur!"minutes"(59);
    const h = dur!"days"(1_000) + t;
    assert(removeDateUnitFromHNSecs(h.total!"hnsecs"()) == t.total!"hnsecs"());
}

unittest // removeTimeUnitFromHNSecs
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.removeTimeUnitFromHNSecs");

    const d = dur!"days"(1_000);
    const h = d + dur!"hours"(1) + dur!"minutes"(59);
    assert(removeTimeUnitFromHNSecs(h.total!"hnsecs"()) == d.total!"hnsecs"());
}

unittest // secondDigitsToDurationSafe
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.secondDigitsToDurationSafe");

    assert(secondDigitsToDurationSafe("123", Duration.zero) == dur!"seconds"(123));
    assert(secondDigitsToDurationSafe("abc", Duration.zero) == Duration.zero);
    assert(secondDigitsToDurationSafe("", Duration.max) == Duration.zero);
}

unittest // toDecimalSafe
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.toDecimalSafe");

    assert(toDecimalSafe!Decimal64("", Decimal64(-1)) == Decimal64(0));
    assert(toDecimalSafe!Decimal64("", Decimal64(-1), Decimal64.max) == Decimal64.max);
    assert(toDecimalSafe!Decimal64("98765432", Decimal64(-1)) == Decimal64(98_765_432));
    assert(toDecimalSafe!Decimal64("-1", Decimal64(0)) == -1);
    assert(toDecimalSafe!Decimal64("-8765324", Decimal64(-1)) == Decimal64(-8_765_324));
}

unittest // toIntegerSafe
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.toIntegerSafe");

    assert(toIntegerSafe!int("", -1) == 0);
    assert(toIntegerSafe!int("", -1, int.max) == int.max);
    assert(toIntegerSafe!int("1", -1) == 1);
    assert(toIntegerSafe!int("98765432", -1) == 98_765_432);
    assert(toIntegerSafe!int("-1", 0) == -1);
    assert(toIntegerSafe!int("-8765324", -1) == -8_765_324);
}

unittest // toStringSafe
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.toStringSafe");

    static int invalidUTF8()
    {
        return 0xFF;
    }

    static int invalidUTF16()
    {
        return 0xDFFF;
    }

    static int invalidUTF32()
    {
        return 0xFFFFFF;
    }

    assert(toStringSafe(char('\0'), failedConvertedString) is null);
    assert(toStringSafe(wchar('\0'), failedConvertedString) is null);
    assert(toStringSafe(dchar('\0'), failedConvertedString) is null);
    assert(toStringSafe(cast(char)invalidUTF8(), failedConvertedString) == failedConvertedString);
    assert(toStringSafe(cast(wchar)invalidUTF16(), failedConvertedString) == failedConvertedString);
    assert(toStringSafe(cast(dchar)invalidUTF32(), failedConvertedString) == failedConvertedString);
    assert(toStringSafe(char('a'), null) == "a");
    assert(toStringSafe(wchar('b'), null) == "b");
    assert(toStringSafe(dchar('c'), null) == "c");
}

unittest // toStringSafe
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.toStringSafe");

    // Need a way to test failure state. D not allow to have invalid string literal
    //assert(toStringSafe("b\uFFFF\uFFFF"w, failedConvertedString) == failedConvertedString);
    //assert(toStringSafe("c\uFFFF\uFFFF"d, failedConvertedString) == failedConvertedString);
    assert(toStringSafe("b"w, null) == "b");
    assert(toStringSafe("c"d, null) == "c");
}

unittest // uintDecode & uintEncode
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.convert.uintDecode & uintEncode");

    // 16 bits
    auto b16 = uintEncode!(ushort, Endian.littleEndian)(ushort.min);
    auto u16 = uintDecode!(ushort, Endian.littleEndian)(b16);
    assert(u16 == ushort.min);

    b16 = uintEncode!(ushort, Endian.littleEndian)(ushort.max);
    u16 = uintDecode!(ushort, Endian.littleEndian)(b16);
    assert(u16 == ushort.max);

    b16 = uintEncode!(ushort, Endian.littleEndian)(0u);
    u16 = uintDecode!(ushort, Endian.littleEndian)(b16);
    assert(u16 == 0u);

    b16 = uintEncode!(ushort, Endian.littleEndian)(ushort.max / 3);
    u16 = uintDecode!(ushort, Endian.littleEndian)(b16);
    assert(u16 == ushort.max / 3);

    assert(uintEncode!(ushort, Endian.littleEndian)(0u) == uintEncode!(ushort, Endian.bigEndian)(0u));
    assert(uintEncode!(ushort, Endian.littleEndian)(ushort.max) == uintEncode!(ushort, Endian.bigEndian)(ushort.max));

    // 32 bits
    auto b32 = uintEncode!(uint, Endian.littleEndian)(uint.min);
    auto u32 = uintDecode!(uint, Endian.littleEndian)(b32);
    assert(u32 == uint.min);

    b32 = uintEncode!(uint, Endian.littleEndian)(uint.max);
    u32 = uintDecode!(uint, Endian.littleEndian)(b32);
    assert(u32 == uint.max);

    b32 = uintEncode!(uint, Endian.littleEndian)(0u);
    u32 = uintDecode!(uint, Endian.littleEndian)(b32);
    assert(u32 == 0u);

    b32 = uintEncode!(uint, Endian.littleEndian)(uint.max / 3);
    u32 = uintDecode!(uint, Endian.littleEndian)(b32);
    assert(u32 == uint.max / 3);

    assert(uintEncode!(uint, Endian.littleEndian)(0u) == uintEncode!(uint, Endian.bigEndian)(0u));
    assert(uintEncode!(uint, Endian.littleEndian)(uint.max) == uintEncode!(uint, Endian.bigEndian)(uint.max));

    // 64 bits
    auto b64 = uintEncode!(ulong, Endian.littleEndian)(ulong.min);
    auto u64 = uintDecode!(ulong, Endian.littleEndian)(b64);
    assert(u64 == ulong.min);

    b64 = uintEncode!(ulong, Endian.littleEndian)(ulong.max);
    u64 = uintDecode!(ulong, Endian.littleEndian)(b64);
    assert(u64 == ulong.max);

    b64 = uintEncode!(ulong, Endian.littleEndian)(0u);
    u64 = uintDecode!(ulong, Endian.littleEndian)(b64);
    assert(u64 == 0u);

    b64 = uintEncode!(ulong, Endian.littleEndian)(ulong.max / 3);
    u64 = uintDecode!(ulong, Endian.littleEndian)(b64);
    assert(u64 == ulong.max / 3);

    assert(uintEncode!(ulong, Endian.littleEndian)(0u) == uintEncode!(ulong, Endian.bigEndian)(0u));
    assert(uintEncode!(ulong, Endian.littleEndian)(ulong.max) == uintEncode!(ulong, Endian.bigEndian)(ulong.max));
}
