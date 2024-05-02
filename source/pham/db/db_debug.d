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

public import std.stdio : writeln;
import std.traits : isFloatingPoint, isIntegral;

string dgToString(scope const(ubyte)[] bytes) nothrow pure @safe
{
    import std.digest : toHexString;
    debug return toHexString(bytes);
}

string dgToString(T)(const(T) n) nothrow pure @safe
if (isIntegral!T)
{    
    import std.conv : to;
    debug return n.to!string;
}
