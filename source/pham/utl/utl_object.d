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
import std.ascii : LetterCase, lowerHexDigits, upperHexDigits=hexDigits, decimalDigits=digits;
import std.conv : to;
import std.exception : assumeWontThrow;
import std.math : isPowerOf2;
import std.traits : isArray, isAssociativeArray, isPointer, isSomeChar, isSomeString, Unqual;

version (TraceInvalidMemoryOp) import pham.utl.test;

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

string currentComputerName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetComputerNameW;

        wchar[256] result = void;
        uint len = result.length - 1;
        if (GetComputerNameW(&result[0], &len))
            return assumeWontThrow(to!string(result[0..len]));
        else
            return "";
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : gethostname;

        char[256] result = void;
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

        wchar[1024] result = void;
        auto len = GetModuleFileNameW(null, &result[0], result.length - 1);
        return assumeWontThrow(to!string(result[0..len]));
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : readlink;

        char[1024] result = void;
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

        wchar[256] result = void;
        uint len = result.length - 1;
        if (GetUserNameW(&result[0], &len))
            return assumeWontThrow(to!string(result[0..len]));
        else
            return "";
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : getlogin_r;

        char[256] result = void;
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

/**
 * Check and convert a 'c' from digit to byte
 * Params:
 *  c = a charater to be checked and converted
 *  b = byte presentation of c's value
 * Returns:
 *  true if c is a valid digit characters, false otherwise
 */
bool isDigit(char c, out ubyte b) @nogc nothrow pure @safe
{
    if (c >= '0' && c <= '9')
    {
        b = cast(ubyte)(c - '0');
        return true;
    }
    else
    {
        b = 0;
        return false;
    }
}

/**
 * Check 'value' is all digits
 * Params:
 *  value = charaters to be checked
 * Returns:
 *  true if value is a valid digit characters, false otherwise
 */
bool isDigits(const(char)[] value) @nogc nothrow pure @safe
{
    foreach (c; value)
    {
        if (c < '0' || c > '9')
            return false;
    }
    return value.length != 0;
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

S pad(S, C)(S value, const(ptrdiff_t) size, C c) nothrow pure @safe
if (isSomeString!S && isSomeChar!C && is(Unqual!(typeof(S.init[0])) == C))
{
    import std.math : abs;

    const n = abs(size);
    if (value.length >= n)
        return value;
    else
        return size > 0
            ? stringOfChar!C(n - value.length, c) ~ value
            : value ~ stringOfChar!C(n - value.length, c);
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
    final void disposal(bool disposing)
    {
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing++;
        doDispose(disposing);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
    }

    final void dispose()
    {
        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));

        _disposing++;
        doDispose(true);

        version (TraceInvalidMemoryOp) dgFunctionTrace(className(this));
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

    int opCmp(T)(const T rhs) const pure
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

    bool opEquals(T)(const T rhs) const pure
    if (is(T == string) || is(Unqual!T == VersionString))
    {
        return opCmp(rhs) == 0;
    }

    static int compare(scope const Parts lhs, scope const Parts rhs) pure
    {
        int result = compare(lhs[0], rhs[0]);
        if (result == 0)
        {
            result = compare(lhs[1], rhs[1]);
            if (result == 0)
            {
                result = compare(lhs[2], rhs[2]);
                if (result == 0)
                    result = compare(lhs[3], rhs[3]);
            }
        }
        return result;
    }

    static int compare(scope const(char)[] lhsPart, scope const(char)[] rhsPart) pure
    {
        scope (failure) assert(0);

        const lhs = to!int(lhsPart);
        const rhs = to!int(rhsPart);
        return lhs == rhs ? 0 : (lhs > rhs ? 1 : -1);
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
        auto result = strip(partString);
        return (result.length <= 9 && isDigits(result)) ? result : "0";
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
    traceUnitTest("unittest utl.object.className");

    auto c1 = new ClassName();
    assert(className(c1) == "pham.utl.object.ClassName");

    auto c2 = new ClassTemplate!int();
    assert(className(c2) == "pham.utl.object.ClassTemplate!int.ClassTemplate");
}

nothrow @safe unittest // currentComputerName
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.currentComputerName");

    assert(currentComputerName().length != 0);
}

nothrow @safe unittest // currentProcessId
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.currentProcessId");

    assert(currentProcessId() != 0);
}

nothrow @safe unittest // currentUserName
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.currentUserName");

    assert(currentUserName().length != 0);
}

nothrow @safe unittest // pad
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.pad");

    assert(pad("", 2, ' ') == "  ");
    assert(pad("12", 2, ' ') == "12");
    assert(pad("12", 3, ' ') == " 12");
    assert(pad("12", -3, ' ') == "12 ");
}

nothrow @safe unittest // shortClassName
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.shortClassName");

    auto c1 = new ClassName();
    assert(shortClassName(c1) == "pham.utl.object.ClassName");

    auto c2 = new ClassTemplate!int();
    assert(shortClassName(c2) == "pham.utl.object.ClassTemplate");
}

unittest // singleton
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.singleton");

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
    traceUnitTest("unittest utl.object.stringOfChar");

    assert(stringOfChar(4, ' ') == "    ");
    assert(stringOfChar(0, ' ').length == 0);
}

unittest // InitializedValue
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.InitializedValue");

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

nothrow @safe unittest // isDigit
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.isDigit");

    ubyte b;

    assert(isDigit('0', b));
    assert(b == 0);

    assert(isDigit('1', b));
    assert(b == 1);

    assert(isDigit('9', b));
    assert(b == 9);

    assert(!isDigit('a', b));
    assert(b == 0);
}

nothrow @safe unittest // isDigits
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.isDigits");

    assert(isDigits("0"));
    assert(isDigits("0123456789"));
    assert(!isDigits(""));
    assert(!isDigits("0ab"));
}

nothrow @safe unittest // isHex
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.isHex");

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
    import pham.utl.test;
    traceUnitTest("unittest utl.object.bytesFromHexs & bytesToHexs");

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

nothrow @safe unittest // VersionString
{
    import pham.utl.test;
    traceUnitTest("unittest utl.object.VersionString");

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
