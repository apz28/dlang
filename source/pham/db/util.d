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

module pham.db.util;

import std.exception : assumeWontThrow;
import std.format : format;
import std.traits: isFloatingPoint, isIntegral;

import pham.db.type;

nothrow @safe:

/*
* Defines a total order on a decimal value vs other.
* Params:
*   lhs = a decimal value
*   rhs = a decimal/integer/float value
* Returns:
*   -1 if x precedes y, 0 if x is equal to y, +1 if x follows y
*   float.nan if any operands is a NaN
*/
float decimalCompare(D, T)(auto const ref D lhs, auto const ref T rhs) @nogc
if (isDecimal!D && (isIntegral!T || isDecimal!T))
{
    import decimal.decimal : cmp;

    return cmp(lhs, rhs);
}

///
float decimalCompare(D, T)(auto const ref D lhs, auto const ref T rhs,
    const int precision = Precision.banking,
    const RoundingMode mode = RoundingMode.banking) @nogc
if (isDecimal!D && isFloatingPoint!T)
{
    import decimal.decimal : cmp;

    return cmp(lhs, rhs, precision, mode);
}

/**
* Compares two _decimal operands for equality
* Returns:
*   true if the specified condition is satisfied, false otherwise or if any of the operands is NaN.
*/
bool decimalEqual(D, T)(auto const ref D lhs, auto const ref T rhs) @nogc
if (isDecimal!D && (isIntegral!T || isDecimal!T))
{
    import decimal.decimal : isEqual;

    return isEqual(lhs, rhs);
}

bool decimalEqual(D, T)(auto const ref D lhs, auto const ref T rhs,
    const int precision = Precision.banking,
    const RoundingMode mode = RoundingMode.banking) @nogc
if (isDecimal!D && isFloatingPoint!T)
{
    import decimal.decimal : isEqual;

   return isEqual(lhs, rhs, precision, mode);
}

string makeCommandName(void* command, uint counter)
{
    scope (failure) assert(0);

    return format("%X_%u", command, counter);
}

/** Returns a string of all integers into its concatenated string separated by separator
    Ex: [1,2,3], "." will returns as "1.2.3"
    Params:
        values = all version parts in integer format
        separator = string that will be used to separate each integer value
    Returns:
        its' string presentation
*/
string toSeparatedString(scope const int[] values, string separator) pure
{
    import std.array : Appender;
    import std.conv : to;

    if (values.length == 0)
        return null;

    Appender!string result;
    result.reserve(values.length * 9);
    foreach (i, v; values)
    {
        if (i)
            result.put(separator);
        result.put(to!string(v));
    }
    return result.data;
}

/** Returns a string of all version parts into its version string format
    Ex: [1,2,3] will returns as "1.2.3"
    Params:
        values = all version parts in integer format
    Returns:
        its' string presentation in v.v.v ...
*/
string toVersionString(scope const int[] values) pure
{
    return toSeparatedString(values, ".");
}

string truncate(return string value, size_t maxLength) pure
{
    return value.length <= maxLength ? value : value[0..maxLength];
}

A truncate(A)(return A value, size_t maxLength) pure
if (is(A == const(char)[]) || is(A == char[]))
{
    return value.length <= maxLength ? value : value[0..maxLength];
}

A truncateEndIf(A)(return A value, size_t ifMaxLength, char ifChar) pure
if (is(A == const(char)[]) || is(A == char[]))
{
    auto length = value.length;
    while (length > ifMaxLength && value[length - 1] == ifChar)
        length--;
    return length == value.length ? value : value[0..length];
}

A truncate(A)(return A value, size_t maxLength) pure
if (is(A == const(ubyte)[]) || is(A == ubyte[]))
{
    return value.length <= maxLength ? value : value[0..maxLength];
}


// Any below codes are private
private:


unittest // truncate
{
    import pham.utl.utltest;
    dgWriteln("unittest db.util.truncate");

    assert(truncate("", 2) == "");
    assert(truncate("123456", 2) == "12");
    assert(truncate("1234567890", 20) == "1234567890");
}

unittest // versionString
{
    import pham.utl.utltest;
    dgWriteln("unittest db.util.versionString");

    assert(toVersionString([]) == "");
    assert(toVersionString([1]) == "1");
    assert(toVersionString([1, 2, 3]) == "1.2.3");
}
