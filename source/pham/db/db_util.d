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

import std.format : format;
import std.traits: isFloatingPoint, isIntegral, isUnsigned;

import pham.external.dec.decimal : isEqual;
import pham.db.type;

nothrow @safe:

pragma(inline, true)
F asFloatBit(I, F)(I v) @nogc pure
if (F.sizeof == I.sizeof && isFloatingPoint!F && isUnsigned!I)
{
    // Use bit cast to avoid any funny float/interger promotion
    return *cast(F*)&v;
}

pragma(inline, true)
I asIntegerBit(F, I)(F v) @nogc pure
if (F.sizeof == I.sizeof && isFloatingPoint!F && isUnsigned!I)
{
    // Use bit cast to avoid any funny float/interger promotion
    return *cast(I*)&v;
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
string toSeparatedString(scope const(int)[] values, const(char)[] separator) pure
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
string toVersionString(scope const(int)[] values) pure
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
    import pham.utl.test;
    traceUnitTest("unittest pham.db.util.truncate");

    assert(truncate("", 2) == "");
    assert(truncate("123456", 2) == "12");
    assert(truncate("1234567890", 20) == "1234567890");
}

unittest // versionString
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.util.versionString");

    assert(toVersionString([]) == "");
    assert(toVersionString([1]) == "1");
    assert(toVersionString([1, 2, 3]) == "1.2.3");
}
