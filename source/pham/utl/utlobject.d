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

module pham.utl.utlobject;

public import std.ascii : LetterCase;
import std.exception : assumeWontThrow;
import std.math : isPowerOf2;
import std.traits : isArray, isAssociativeArray, isPointer;

pragma(inline, true);
size_t alignRoundup(size_t n, size_t powerOf2AlignmentSize) @nogc nothrow pure @safe
in
{
    assert(powerOf2AlignmentSize > 1);
    assert(isPowerOf2(powerOf2AlignmentSize));
}
do
{
    return (n + powerOf2AlignmentSize - 1) & ~(powerOf2AlignmentSize - 1);
}

immutable string decimalDigits = "0123456789";
immutable string lowerHexDigits = "0123456789abcdef";
immutable string upperHexDigits = "0123456789ABCDEF";

ubyte[] bytesFromHexs(scope const(char)[] validHexChars) nothrow pure @safe
{
    const resultLength = (validHexChars.length / 2) + (validHexChars.length % 2);
    auto result = new ubyte[resultLength];
    size_t bitIndex = 0;
    bool shift = false;
    ubyte b = 0;
    for (auto i = 0; i < validHexChars.length; i++)
    {
        if (!isHex(validHexChars[i], b))
        {
            switch (validHexChars[i])
            {
                case ' ':
                case '_':
                    continue;
                default:
                    assert(0);
            }
        }

        if (shift)
        {
            result[bitIndex] = cast(ubyte)((result[bitIndex] << 4) | b);
            bitIndex++;
        }
        else
        {
            result[bitIndex] = b;
        }
        shift = !shift;
    }
    return result;
}

/**
 * Convert byte array to its hex presentation
 * Params:
 *  bytes = bytes to be converted
 * Returns:
 *  array of characters
 */
char[] bytesToHexs(LetterCase letterCase = LetterCase.upper)(scope const(ubyte)[] bytes) nothrow pure @safe
{
    char[] result;
    if (bytes.length)
    {
        enum hexDigitSources = letterCase == LetterCase.upper ? upperHexDigits : lowerHexDigits;
        result.length = bytes.length * 2;
        size_t i;
        foreach (b; bytes)
        {
            result[i++] = hexDigitSources[(b >> 4) & 0xF];
            result[i++] = hexDigitSources[b & 0xF];
        }
    }
    return result;
}

/**
 * Returns the class-name of object. If it is null, returns "null"
 * Params:
 *   object = the object to get the class-name from
 */
string className(Object object) nothrow pure @safe
{
    if (object is null)
        return "null";
    else
        return typeid(object).name;
}

string functionName(string name = __FUNCTION__) nothrow pure @safe
{
    return name;
}

string functionName(T)(string name = __FUNCTION__) nothrow pure @safe
if (is(T == class) || is(T == struct))
{
    return shortenTypeName(T.stringof) ~ "." ~ name;
}

/**
 * Check and convert a 'c' from hex to byte
 * Params:
 *  c = a charater to be checked and converted
 *  b = byte presentation of c's value
 * Returns:
 *  true if c is a valid hex characters, false otherwise
 */
bool isHex(char c, out ubyte b) @nogc nothrow pure @safe
{
    if (c >= '0' && c <= '9')
        b = cast(ubyte)(c - '0');
    else if (c >= 'A' && c <= 'F')
        b = cast(ubyte)((c - 'A') + 10);
    else if (c >= 'a' && c <= 'f')
        b = cast(ubyte)((c - 'a') + 10);
    else
    {
        b = 0;
        return false;
    }

    return true;
}

char[] randomCharacters(size_t numCharacters) nothrow pure @safe
{
    import std.range : Appender;
    import std.random;

    if (numCharacters == 0)
        return null;

    Appender!(char[]) result;
    result.reserve(numCharacters);
    auto rnd = Random();
    size_t l = 0;
    while (l < numCharacters)
    {
        auto i = assumeWontThrow(uniform(0, 127, rnd));
        if (i != 0)
        {
            result.put(cast(char)i);
            ++l;
        }
    }
    return result.data;
}

/**
 * Generate array of digit characters
 * Params:
 *  numDigits = number of digit characters
 *  leadingIndicator = not being used, for same function signature with randomHexDigits
 */
char[] randomDecimalDigits(size_t numDigits,
    bool leadingIndicator = true) nothrow pure @safe
{
    import std.range : Appender;
    import std.random;

    if (numDigits == 0)
        return ['0'];

    Appender!(char[]) result;
    result.reserve(numDigits);
    auto rnd = Random();
    size_t l = 0;
    while (l < numDigits)
    {
        auto i = assumeWontThrow(uniform(0, decimalDigits.length, rnd));
        auto c = decimalDigits[i];
        // Can not generate leading zero
        if (l != 0 || c != '0')
        {
            result.put(c);
            ++l;
        }
    }
    return result.data;
}

/**
 * Generate array of hex characters
 * Params:
 *  numDigits = number of hex characters
 *  leadingIndicator = should "0x0" be added to be leading characters?
 */
char[] randomHexDigits(size_t numDigits,
    bool leadingIndicator = true) nothrow pure @safe
{
    import std.range : Appender;
    import std.random;

    if (numDigits == 0)
        return leadingIndicator ? ['0','x','0','0'] : ['0'];

    Appender!(char[]) result;
    result.reserve(numDigits + (leadingIndicator ? 3 : 0));
    if (leadingIndicator)
        result.put("0x0"); // Leading zero to indicate positive number
    auto rnd = Random();
    size_t l = 0;
    while (l < numDigits)
    {
        auto i = assumeWontThrow(uniform(0, upperHexDigits.length, rnd));
        auto c = upperHexDigits[i];
        // Can not generate leading zero
        if (l != 0 || c != '0')
        {
            result.put(c);
            ++l;
        }
    }
    return result.data;
}

/**
 * Returns the short class-name of object without template type. If it is null, returns "null"
 * Params:
 *   object = the object to get the class-name from
 */
string shortClassName(Object object) nothrow pure @safe
{
    if (object is null)
        return "null";
    else
        return shortenTypeName(typeid(object).name);
}

string shortenTypeName(string fullName) nothrow pure @safe
{
    import std.algorithm.iteration : filter;
    import std.array : join, split;
    import std.string : indexOf;

    return split(fullName, ".").filter!(e => e.indexOf('!') < 0).join(".");
}

string shortTypeName(T)() nothrow pure @safe
if (is(T == class) || is(T == struct))
{
    return shortenTypeName(T.stringof);
}

/**
 * Initialize parameter v if it is null in thread safe manner using pass in initiate function
 * Params:
 *   v = variable to be initialized to object T if it is null
 *   initiate = a function that returns the newly created object as of T
 * Returns:
 *   parameter v
 */
T singleton(T)(ref T v, T function() nothrow pure @safe initiate) nothrow pure @trusted //@trusted=cast(T)null
if (is(T == class))
{
    import core.atomic : cas;
    import std.traits : hasElaborateDestructor;

    if (v is null)
    {
        auto n = initiate();
        if (!cas(&v, cast(T)null, n))
        {
            static if (hasElaborateDestructor!T)
                n.__xdtor();
        }
    }

    return v;
}

enum DisposableState : byte
{
    none,
    disposing,
    destructing
}

interface IDisposable
{
nothrow @safe:

    void disposal(bool disposing);
    void dispose();
}

abstract class DisposableObject : IDisposable
{
nothrow @safe:

public:
    ~this()
    {
        version (TraceInvalidMemoryOp) import pham.utl.utltest : dgFunctionTrace;
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing = byte.min; // Set to min avoid ++ then --
        doDispose(false);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
    }

    final void disposal(bool disposing)
    {
        if (!disposing)
            _disposing = byte.min; // Set to min avoid ++ then --

        _disposing++;
        scope (exit)
            _disposing--;

        doDispose(disposing);
    }

    final void dispose()
    {
        _disposing++;
        scope (exit)
            _disposing--;

        doDispose(true);
    }

    @property final DisposableState disposingState() const
    {
        if (_disposing == 0)
            return DisposableState.none;
        else if (_disposing > 0)
            return DisposableState.disposing;
        else
            return DisposableState.destructing;
    }

protected:
    abstract void doDispose(bool disposing);

private:
    byte _disposing;
}

struct InitializedValue(T)
{
nothrow @safe:

public:
    this(T value)
    {
        this._value = value;
        this._inited = true;
    }

    ref typeof(this) opAssign(T)(T value) return
    {
        this._value = value;
        this._inited = true;
        return this;
    }

    C opCast(C: bool)() const
    {
        if (_inited)
        {
            static if (isPointer!T || is(T == class))
                return _value !is null;
            else static if (isArray!T || isAssociativeArray!T)
                return _value.length != 0;
            else
                return true;
        }
        else
            return false;
    }

    void reset()
    {
        if (_inited)
        {
            _value = T.init;
            _inited = false;
        }
    }

    @property bool inited() const
    {
        return _inited;
    }

    @property inout(T) value() inout pure
    in
    {
        assert(_inited, "value must be set before using!");
    }
    do
    {
        return _value;
    }

    alias value this;

private:
    T _value;
    bool _inited;
}


// Any below codes are private
private:


version (unittest)
{
    class ClassName {}

    class ClassTemplate(T) {}
}

nothrow @safe unittest // className
{
    import pham.utl.utltest;
    dgWriteln("unittest utl.utlobject.className");

    auto c1 = new ClassName();
    assert(className(c1) == "pham.utl.utlobject.ClassName");

    auto c2 = new ClassTemplate!int();
    assert(className(c2) == "pham.utl.utlobject.ClassTemplate!int.ClassTemplate");
}

nothrow @safe unittest // shortClassName
{
    import pham.utl.utltest;
    dgWriteln("unittest utl.utlobject.shortClassName");

    auto c1 = new ClassName();
    assert(shortClassName(c1) == "pham.utl.utlobject.ClassName");

    auto c2 = new ClassTemplate!int();
    assert(shortClassName(c2) == "pham.utl.utlobject.ClassTemplate");
}

unittest // singleton
{
    import pham.utl.utltest;
    dgWriteln("unittest utl.utlobject.singleton");

    static class A {}

    static A createA() pure @safe
    {
        return new A;
    }

    A a;
    assert(a is null);
    assert(singleton(a, &createA) !is null);
}

unittest // InitializedValue
{
    import pham.utl.utltest;
    dgWriteln("unittest utl.utlobject.InitializedValue");

    InitializedValue!int n;
    assert(!n);
    assert(!n.inited);

    n = 0;
    assert(n);
    assert(n.inited);
    assert(n == 0);

    InitializedValue!ClassName c;
    assert(!c);
    assert(!c.inited);

    c = null;
    assert(!c);
    assert(c.inited);

    c = new ClassName();
    assert(c);
    assert(c.inited);
    assert(c !is null);
}

nothrow @safe unittest // isHex
{
    import pham.utl.utltest;
    dgWriteln("unittest utl.utlobject.isHex");

    ubyte b;

    assert(isHex('0', b));
    assert(b == 0);

    assert(isHex('a', b));
    assert(b == 10);

    assert(!isHex('z', b));
    assert(b == 0);
}

nothrow @safe unittest // bytesFromHexs & bytesToHexs
{
    import pham.utl.utltest;
    dgWriteln("unittest utl.utlobject.bytesFromHexs & bytesToHexs");

    assert(bytesToHexs([0]) == "00");
    assert(bytesToHexs([1]) == "01");
    assert(bytesToHexs([15]) == "0F");
    assert(bytesToHexs([255]) == "FF");

    assert(bytesFromHexs("00") == [0]);
    assert(bytesFromHexs("01") == [1]);
    assert(bytesFromHexs("0F") == [15]);
    assert(bytesFromHexs("FF") == [255]);

    enum testHexs = "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443";
    auto bytes = bytesFromHexs(testHexs);
    assert(bytesToHexs(bytes) == testHexs);
}
