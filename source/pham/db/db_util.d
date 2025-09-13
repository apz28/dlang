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

nothrow @safe:

int breakSymbol(string fullSymbol, out string schemaOrTable, out string symbol) nothrow pure
{
    import pham.utl.utl_array : indexOf;

    if (fullSymbol.length == 0)
    {
        schemaOrTable = symbol = null;
        return 0;
    }

    const i = fullSymbol.indexOf('.');
    if (i >= 0)
    {
        schemaOrTable = fullSymbol[0..i];
        symbol = fullSymbol[i+1..$];
        return 2;
    }
    else
    {
        schemaOrTable = null;
        symbol = fullSymbol;
        return 1;
    }
}

string combineSymbol(string schemaOrTable, string symbol) nothrow pure
{
    return schemaOrTable.length ? (schemaOrTable ~ "." ~ symbol) : symbol;
}

version(none)
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

version(none)
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

version(none)
char isQuoted(scope const(char)[] symbol) @nogc nothrow pure
{
    if (symbol.length <= 1)
        return '\0';

    const first = symbol[0];
    return first == symbol[$-1] && (first == '"' || first == '\'' || first == '`')
        ? first
        : '\0';
}

string makeCommandName(const(void*) command, uint counter)
{
    import pham.utl.utl_array_append : Appender;
    import pham.utl.utl_convert : putNumber;

    auto result = Appender!string((size_t.sizeof * 2) + 10 + 2);
    return result.put('x') // Name must start with a character, so pick one
        .putNumber!16(cast(size_t)command)
        .put('_')
        .putNumber(counter)
        .data;
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
    import pham.utl.utl_array_append : Appender;
    import pham.utl.utl_convert : putNumber;

    if (values.length == 0)
        return null;

    auto result = Appender!string(values.length * 10);
    foreach (v; values)
    {
        if (result.length)
            result.put(separator);
        result.putNumber(v);
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

A truncate(A)(return A value, size_t maxLength) pure
if (is(A == const(ubyte)[]) || is(A == ubyte[]))
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


// Any below codes are private
private:

unittest // combineSymbol
{
    assert(combineSymbol(null, "xyz") == "xyz");
    assert(combineSymbol("ABC", "xyz") == "ABC.xyz");
}

unittest // breakSymbol
{
    string s1, s2;

    assert(breakSymbol(null, s1, s2) == 0);
    assert(s1.length == 0);
    assert(s2.length == 0);

    assert(breakSymbol("xyz", s1, s2) == 1);
    assert(s1.length == 0);
    assert(s2 == "xyz");

    assert(breakSymbol("ABC.", s1, s2) == 2);
    assert(s1 == "ABC");
    assert(s2.length == 0);

    assert(breakSymbol("ABC.xyz", s1, s2) == 2);
    assert(s1 == "ABC");
    assert(s2 == "xyz");
}

unittest // truncate
{
    assert(truncate("", 2) == "");
    assert(truncate("123456", 2) == "12");
    assert(truncate("1234567890", 20) == "1234567890");
}

unittest // versionString
{
    assert(toVersionString([]) == "");
    assert(toVersionString([1]) == "1");
    assert(toVersionString([1, 2, 3]) == "1.2.3");
}

@trusted unittest // makeCommandName
{
    assert(makeCommandName(null, 20) == "x0_20");
    assert(makeCommandName(cast(void*)0x1234Abc, 20) == "x1234ABC_20");
}
