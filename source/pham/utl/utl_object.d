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

module pham.utl.object;

import core.sync.mutex : Mutex;
public import std.ascii : LetterCase;
import std.ascii : lowerHexDigits, upperHexDigits=hexDigits, decimalDigits=digits;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.format : FormatSpec;
import std.math : isPowerOf2;
import std.range.primitives : put;
import std.traits : isArray, isAssociativeArray, isFloatingPoint, isIntegral, isPointer,
    isSomeChar, isSomeString, isUnsigned, Unqual;

version (TraceInvalidMemoryOp) import pham.utl.test;
import pham.utl.utf8 : isHexDigit, NumericParsedKind, parseHexDigits, parseIntegral, ShortStringBuffer;

pragma(inline, true);
size_t alignRoundup(const(size_t) n, const(size_t) powerOf2AlignmentSize) @nogc nothrow pure @safe
in
{
    assert(powerOf2AlignmentSize > 1);
    assert(isPowerOf2(powerOf2AlignmentSize));
}
do
{
    return (n + powerOf2AlignmentSize - 1) & ~(powerOf2AlignmentSize - 1);
}

ubyte[] bytesFromHexs(scope const(char)[] validHexDigits) nothrow pure @safe
{
    struct R
    {
    @nogc nothrow pure @safe:
        @property bool empty() const
        {
            return i >= length;
        }

        char front() const
        {
            return validHexDigits[i];
        }

        void popFront()
        {
            i++;
        }

        size_t i, length;
    }

    auto r = R(0, validHexDigits.length);
    ShortStringBuffer!ubyte buffer;
    parseHexDigits(r, buffer);
    return buffer[].dup;
}

/**
 * Convert byte array to its hex presentation
 * Params:
 *  bytes = bytes to be converted
 * Returns:
 *  array of characters
 */
char[] bytesToHexs(scope const(ubyte)[] bytes,
    const(LetterCase) letterCase = LetterCase.upper) nothrow pure @safe
{
    char[] result;
    if (bytes.length)
    {
        const hexDigits = letterCase == LetterCase.upper ? upperHexDigits : lowerHexDigits;
        result.length = bytes.length * 2;
        size_t i;
        foreach (b; bytes)
        {
            result[i++] = hexDigits[(b >> 4) & 0xF];
            result[i++] = hexDigits[b & 0xF];
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

pragma(inline, true)
int cmpInteger(T)(const(T) lhs, const(T) rhs) @nogc nothrow pure @safe
if (isIntegral!T)
{
    return (lhs > rhs) - (lhs < rhs);
}

pragma(inline, true)
float cmpFloat(T)(const(T) lhs, const(T) rhs) @nogc nothrow pure @safe
if (isFloatingPoint!T)
{
    import std.math : isNaN;

    if (isNaN(lhs) || isNaN(rhs))
        return float.nan;
    else
        return (lhs > rhs) - (lhs < rhs);
}

string currentComputerName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetComputerNameW;

        wchar[1000] result = void;
        uint len = result.length - 1;
        if (GetComputerNameW(&result[0], &len))
            return assumeWontThrow(to!string(result[0..len]));
        else
            return "";
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : gethostname;

        char[1000] result = void;
        uint len = result.length - 1;
        if (gethostname(&result[0], len) == 0)
            return assumeWontThrow(to!string(result.ptr));
        else
            return "";
    }
    else
    {
        pragma(msg, "currentComputerName() not supported");
        return "";
    }
}

uint currentProcessId() nothrow @safe
{
    import std.process : thisProcessID;

    return thisProcessID;
}

string currentProcessName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetModuleFileNameW;

        wchar[1000] result = void;
        auto len = GetModuleFileNameW(null, &result[0], result.length - 1);
        return assumeWontThrow(to!string(result[0..len]));
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : readlink;

        char[1000] result = void;
        uint len = result.length - 1;
        len = readlink("/proc/self/exe".ptr, &result[0], len);
        return result[0..len].idup;
    }
    else
    {
        pragma(msg, "currentProcessName() not supported");
        return "";
    }
}

string currentUserName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetUserNameW;

        wchar[1000] result = void;
        uint len = result.length - 1;
        if (GetUserNameW(&result[0], &len))
            return assumeWontThrow(to!string(result[0..len]));
        else
            return "";
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : getlogin_r;

        char[1000] result = void;
        uint len = result.length - 1;
        if (getlogin_r(&result[0], len) == 0)
            return assumeWontThrow(to!string(&result[0]));
        else
            return "";
    }
    else
    {
        pragma(msg, "currentUserName() not supported");
        return "";
    }
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

S pad(S, C)(S value, const(ptrdiff_t) size, C c) nothrow pure @safe
if (isSomeString!S && isSomeChar!C && is(Unqual!(typeof(S.init[0])) == C))
{
    import std.math : abs;

    const n = abs(size);
    if (value.length >= n)
        return value;
    else
        return size > 0
            ? (stringOfChar!C(n - value.length, c) ~ value)
            : (value ~ stringOfChar!C(n - value.length, c));
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

FormatSpec!char simpleFloatFmt() nothrow pure @safe
{
    FormatSpec!char result;
    result.spec = 'f';
    return result;
}

FormatSpec!char simpleIntegerFmt(int width = 0) nothrow pure @safe
{
    FormatSpec!char result;
    result.spec = 'd';
    result.width = width;
    return result;
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

auto stringOfChar(C = char)(size_t count, C c) nothrow pure @trusted
if (is(Unqual!C == char) || is(Unqual!C == wchar) || is(Unqual!C == dchar))
{
    auto result = new Unqual!C[count];
    result[] = c;
    static if (is(Unqual!C == char))
        return cast(string)result;
    else static if (is(Unqual!C == wchar))
        return cast(wstring)result;
    else
        return cast(dstring)result;
}

ref Writer toString(uint radix = 10, N, Writer)(return ref Writer sink, N n,
    const(ubyte) padSize = 0, const(char) padChar = '0',
    const(LetterCase) letterCase = LetterCase.upper) nothrow pure @safe
if (isIntegral!N && (radix == 2 || radix == 8 || radix == 10 || radix == 16))
{
    alias UN = Unqual!N;
    enum bufSize = 300;

    char[bufSize] bufDigits;
    size_t bufIndex = bufSize;
    const isNeg = radix == 10 && n < 0;

    static if (radix == 10)
    {
        UN un = isNeg ? -n : n;
        while (un >= 10)
        {
            bufDigits[--bufIndex] = decimalDigits[un % 10];
            un /= 10;
        }
        bufDigits[--bufIndex] = decimalDigits[un];
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
            static assert(false);

        const radixDigits = letterCase == LetterCase.upper ? upperHexDigits : lowerHexDigits;
        UN un = n;
        do
        {
            bufDigits[--bufIndex] = radixDigits[un & mask];
        }
        while (un >>>= shift);
    }

    if (padSize)
    {
        size_t cn = isNeg ? (bufSize - bufIndex + 1) : (bufSize - bufIndex);
        while (padSize > cn)
        {
            bufDigits[--bufIndex] = padChar;
            cn++;
        }
    }

    if (isNeg)
        bufDigits[--bufIndex] = '-';

    put(sink, bufDigits[bufIndex..bufSize]);
    return sink;
}

enum DisposableState : ubyte
{
    none,
    disposing,
    destructing,
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
    final void disposal(bool disposing)
    {
        _disposing++;
        doDispose(disposing);
    }

    final void dispose()
    {
        _disposing++;
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

    ref typeof(this) reset() return
    {
        if (_inited)
        {
            _value = T.init;
            _inited = false;
        }
        return this;
    }

    @property bool inited() const pure
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

struct RAIIMutex
{
@nogc nothrow @safe:

public:
    @disable this();
    @disable this(ref typeof(this));
    @disable void opAssign(typeof(this));

    this(Mutex mutex)
    {
        this._locked = 0;
        this._mutex = mutex;
        lock();
    }

    ~this()
    {
        if (_locked > 0)
            unlock();
        _mutex = null;
    }

    void lock()
    {
        if (_locked++ == 0 && _mutex !is null)
            _mutex.lock_nothrow();
    }

    void unlock()
    in
    {
        assert(_locked > 0);
    }
    do
    {
        if (--_locked == 0 && _mutex !is null)
            _mutex.unlock_nothrow();
    }

    @property int locked() const pure
    {
        return _locked;
    }

private:
    Mutex _mutex;
    int _locked;
}

struct ResultStatus
{
nothrow @safe:

public:
    this(bool okStatus, int errorCode, string errorMessage) @nogc pure
    {
        this.okStatus = okStatus;
        this.errorCode = errorCode;
        this.errorMessage = errorMessage;
    }

    bool opCast(C: bool)() const @nogc pure
    {
        return okStatus;
    }

    pragma(inline, true)
    static typeof(this) error(int errorCode, string errorMessage) @nogc pure
    {
        return ResultStatus(false, errorCode, errorMessage);
    }

    pragma(inline, true)
    static typeof(this) ok() @nogc pure
    {
        return ResultStatus(true, 0, null);
    }

public:
    bool okStatus;
    int errorCode;
    string errorMessage;
}

struct VersionString
{
import std.array : join, split;
import std.string : strip;

nothrow @safe:

public:
    alias Parts = string[4];

public:
    this(string versionString) pure
    {
        this.parts = parse(versionString);
    }

    int opCmp(T)(const(T) rhs) const pure
    if (is(T == string) || is(Unqual!T == VersionString))
    {
        static if (is(Unqual!T == VersionString))
        {
            alias rhsVersion = rhs;
        }
        else
        {
            const tmpVersion = VersionString(rhs);
            alias rhsVersion = tmpVersion;
        }
        return compare(this.parts, rhsVersion.parts);
    }

    bool opEquals(T)(const(T) rhs) const pure
    if (is(T == string) || is(Unqual!T == VersionString))
    {
        return opCmp(rhs) == 0;
    }

    static int compare(scope const(Parts) lhs, scope const(Parts) rhs) pure
    {
        foreach (i; 0..4)
        {
            const result = compare(lhs[i], rhs[i]);
            if (result != 0)
                return result;
        }
        return 0;
    }

    static int compare(scope const(char)[] lhsPart, scope const(char)[] rhsPart) pure
    {
        uint lhs, rhs;
        if (parseIntegral(lhsPart, lhs) != NumericParsedKind.ok)
            return 2;
        if (parseIntegral(rhsPart, rhs) != NumericParsedKind.ok)
            return -2;

        return cmpInteger(lhs, rhs);
    }

    static Parts parse(string versionString) pure
    {
        Parts result = ["0", "0", "0", "0"];
        if (versionString.length != 0)
        {
            auto versions = split(versionString, ".");
            if (versions.length > 0)
                result[0] = part(versions[0]);
            if (versions.length > 1)
                result[1] = part(versions[1]);
            if (versions.length > 2)
                result[2] = part(versions[2]);
            if (versions.length > 3)
                result[3] = part(versions[3]);
        }
        return result;
    }

    static string part(string partString) pure
    {
        uint n;
        auto result = strip(partString);
        return parseIntegral(result, n) == NumericParsedKind.ok ? result : "0";
    }

    string toString() const pure
    {
        return parts[].join(".");
    }

public:
    Parts parts;
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
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.className");

    auto c1 = new ClassName();
    assert(className(c1) == "pham.utl.object.ClassName");

    auto c2 = new ClassTemplate!int();
    assert(className(c2) == "pham.utl.object.ClassTemplate!int.ClassTemplate");
}

nothrow @safe unittest // currentComputerName
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.currentComputerName");

    assert(currentComputerName().length != 0);
}

nothrow @safe unittest // currentProcessId
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.currentProcessId");

    assert(currentProcessId() != 0);
}

nothrow @safe unittest // currentUserName
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.currentUserName");

    assert(currentUserName().length != 0);
}

nothrow @safe unittest // pad
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.pad");

    assert(pad("", 2, ' ') == "  ");
    assert(pad("12", 2, ' ') == "12");
    assert(pad("12", 3, ' ') == " 12");
    assert(pad("12", -3, ' ') == "12 ");
}

nothrow @safe unittest // shortClassName
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.shortClassName");

    auto c1 = new ClassName();
    assert(shortClassName(c1) == "pham.utl.object.ClassName");

    auto c2 = new ClassTemplate!int();
    assert(shortClassName(c2) == "pham.utl.object.ClassTemplate");
}

unittest // singleton
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.singleton");

    static class A {}

    static A createA() pure @safe
    {
        return new A;
    }

    A a;
    assert(a is null);
    assert(singleton(a, &createA) !is null);
}

nothrow @safe unittest // stringOfChar
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.stringOfChar");

    assert(stringOfChar(4, ' ') == "    ");
    assert(stringOfChar(0, ' ').length == 0);
}

unittest // InitializedValue
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.InitializedValue");

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

nothrow @safe unittest // bytesFromHexs & bytesToHexs
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.bytesFromHexs & bytesToHexs");

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

    enum testHexs = "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443";
    auto bytes = bytesFromHexs(testHexs);
    assert(bytesToHexs(bytes) == testHexs);
}

nothrow @safe unittest // VersionString
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.VersionString");

    const v1Str = "1.2.3.4";
    const v1 = VersionString(v1Str);
    assert(v1.parts[0] == "1");
    assert(v1.parts[1] == "2");
    assert(v1.parts[2] == "3");
    assert(v1.parts[3] == "4");
    assert(v1.toString() == v1Str);

    const v2Str = "1.2.0.0";
    const v2 = VersionString("1.2");
    assert(v2.parts[0] == "1");
    assert(v2.parts[1] == "2");
    assert(v2.parts[2] == "0");
    assert(v2.parts[3] == "0");
    assert(v2.toString() == v2Str);

    assert(v1 > v2);
    assert(v1 == VersionString(v1Str));
    assert(v1 == v1Str);
    assert(v2 == v2Str);
    assert(v2 == VersionString(v2Str));

    auto vNull = VersionString("");
    assert(vNull.toString() == "0.0.0.0");
    assert(vNull < "1.2.3.4");
    assert("1.2.3.4" > vNull);
}

@safe unittest // toString
{
    import std.array : Appender;
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.toString");

    void testCheck(uint radix = 10, N)(N n, const(ubyte) pad, string expected,
        size_t line = __LINE__)
    {
        Appender!string buffer;
        toString!(radix, N)(buffer, n, pad);
        assert(buffer.data == expected, to!string(line) ~ ": " ~ buffer.data ~ " vs " ~ expected);
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

    testCheck!(2)(2U, 0, "10");
    testCheck!(2)(2U, 4, "0010");

    testCheck!(16)(255U, 0, "FF");
    testCheck!(16)(255U, 4, "00FF");

    // Test default call
    Appender!string buffer;
    assert(toString(buffer, 10).data == "10");
}
