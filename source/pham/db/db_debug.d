/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.db_debug;

import std.traits : isIntegral;

string dgLimitString(scope const(char)[] chars, size_t limit = 100) nothrow pure @safe
{
    import std.array : Appender;
    //import std.ascii : newline;

    if (chars.length <= limit)
        return chars.idup;

    Appender!string result;
    while (chars.length)
    {
        const count = chars.length > limit ? limit : chars.length;
        result.put(chars[0..count]);
        result.put('\n');
        chars = chars[count..$];
    }
    return result[];
}

string dgToString(scope const(ubyte)[] bytes) nothrow pure @safe
{
    import std.digest : toHexString;
    debug return bytes.length == 0 ? "" : dgLimitString(toHexString(bytes));
}

string dgToString(scope const(char)[] chars) nothrow pure @safe
{
    return chars.length == 0 ? "" : dgLimitString(chars);
}

string dgToString(T)(const(T) n) nothrow pure @safe
if (isIntegral!T)
{
    import std.conv : to;
    debug return n.to!string;
}

void writeln(S...)(S args)
{
    import std.stdio : stdout, write;

    debug write(args, '\n');
    debug stdout.flush();
}

void writelnFor(scope string[] lines, const(uint) beginCount, const(uint) endCount)
{
    size_t i = 0;
    uint count = beginCount;
    while (count)
    {
        if (i < lines.length)
        {
            writeln(lines[i]);
            i++;
        }
        count--;
    }

    if (lines.length > beginCount)
    {
        i = lines.length;
        count = endCount;
        while (count)
        {
            if (i > beginCount)
            {
                writeln(lines[i - 1]);
                i--;
            }
            count--;
        }
    }
}

struct DgMarker
{
nothrow @safe:

    static immutable string sep = "----------";

    this(string marker)
    {
        this.marker = marker;
        debug writeln("\nBEG", sep, "\n", marker, "\n", sep, "---\n");
    }

    ~this()
    {
        debug writeln("\n", sep, "---\n", marker, "\nEND", sep, "\n");
    }

    string marker;
}