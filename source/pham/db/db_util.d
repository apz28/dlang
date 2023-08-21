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

module pham.db.db_util;

import pham.db.db_type;

nothrow @safe:

version (none)
string dictionaryGet(ref const(string[string]) values, string name, string notFoundValue) pure
in
{
    assert(name.length != 0);
}
do
{
    if (auto e = name in values)
        return *e;
    else
        return notFoundValue;
}

version (none)
string dictionaryPut(ref string[string] values, string name, string value) pure
in
{
    assert(name.length != 0);
}
do
{
    if (value.length != 0)
        values[name] = value;
    else
        values.remove(name);
    return value;
}

string makeCommandName(void* command, uint counter)
{
    import std.format : format;

    scope (failure) assert(0, "Assume nothrow failed");

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

pragma(inline, true)
size_t truncate(size_t value, size_t max) @nogc pure
{
    return value <= max ? value : max;
}

pragma(inline, true)
string truncate(return string value, size_t maxLength) @nogc pure
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
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.util.truncate");

    assert(truncate("", 2) == "");
    assert(truncate("123456", 2) == "12");
    assert(truncate("1234567890", 20) == "1234567890");
}

unittest // versionString
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.util.versionString");

    assert(toVersionString([]) == "");
    assert(toVersionString([1]) == "1");
    assert(toVersionString([1, 2, 3]) == "1.2.3");
}
