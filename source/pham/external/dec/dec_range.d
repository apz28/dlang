module pham.external.dec.range;

import std.range.primitives: isInputRange;
import std.traits: isSomeChar;

nothrow @safe:
package(pham.external.dec):

//rewrite some range primitives because phobos is performing utf decoding and we are not interested
//in throwing UTFException and consequentely bring the garbage collector into equation
//Also, we don't need any decoding, we are working with the ASCII character set
@property bool empty(T)(scope const(T)[] s) @safe pure nothrow @nogc
{
    return !s.length;
}

@property T front(T)(const T[] s) @safe pure nothrow @nogc
in
{
    assert(s.length);
}
do
{
    return s[0];
}

void popFront(T)(ref T[] s) @safe pure nothrow @nogc
in
{
    assert(s.length);
}
do
{
    s = s[1 .. $];
}

//returns true and advance range if element is found
bool expect(R, T)(ref R range, T element) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!T)
{
    if (!range.empty && range.front == element)
    {
        range.popFront();
        return true;
    }
    return false;
}

unittest
{
    auto s = "abc";
    assert(expect(s, 'a'));
    assert(!expect(s, 'B'));
    assert(expect(s, 'b'));
    assert(expect(s, 'c'));
    assert(!expect(s, 'd'));
}

//returns parsed characters count and advance range
size_t expect(R, C)(ref R range, const(C)[] s) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!C)
{
    size_t result = 0;
    foreach (ch; s)
    {
        if (expect(range, ch))
            ++result;
        else
            break;
    }
    return result;
}

unittest
{
    auto s = "somestring";
    assert(expect(s, "some") == 4);
    assert(expect(s, "spring") == 1);
    assert(expect(s, "bring") == 0);
    assert(expect(s, "tring") == 5);
}

//returns true and advance range if element is found case insensitive
bool expectInsensitive(R, T)(ref R range, T element) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!T)
{
    if (!range.empty && ((range.front | 32) == (element | 32)))
    {
        range.popFront();
        return true;
    }
    return false;
}

unittest
{
    auto s = "abcABC";
    assert(expectInsensitive(s, 'a'));
    assert(!expectInsensitive(s, 'z'));
    assert(expectInsensitive(s, 'B'));
    assert(expectInsensitive(s, 'c'));
    assert(expectInsensitive(s, 'A'));
    assert(expectInsensitive(s, 'b'));
    assert(expectInsensitive(s, 'C'));
    assert(!expectInsensitive(s, 'd'));
    assert(!expectInsensitive(s, 'D'));
}

//returns parsed characters count and advance range insensitive
size_t expectInsensitive(R, C)(ref R range, const(C)[] s) @safe pure nothrow @nogc
if (isInputRange!R && isSomeChar!C)
{
    size_t result = 0;
    foreach(ch; s)
    {
        if (expectInsensitive(range, ch))
            ++result;
        else
            break;
    }
    return result;
}

unittest
{
    auto s = "sOmEsTrInG";
    assert(expectInsensitive(s, "SoME") == 4);
    assert(expectInsensitive(s, "SPRing") == 1);
    assert(expectInsensitive(s, "bRING") == 0);
    assert(expectInsensitive(s, "TRinG") == 5);
}
