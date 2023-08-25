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

module pham.utl.utl_object;

import core.sync.mutex : Mutex;
public import std.ascii : LetterCase;
import std.format : FormatSpec;
import std.math : isPowerOf2;
import std.range.primitives : put;
import std.traits : isArray, isAssociativeArray, isIntegral, isPointer,
    isSomeChar, isSomeString, isUnsigned, Unqual;

import pham.utl.utl_array : ShortStringBuffer;
import pham.utl.utl_disposable;
import pham.utl.utl_numeric_parser : Base64MappingChar, NumericParsedKind, cvtBytesBase64, cvtBytesHex, parseBase64, parseHexDigits;
import pham.utl.utl_result : cmp;
import pham.utl.utl_utf8 : NoDecodeInputRange;

/**
 * Roundups and returns value, `n`, to the power of 2 modular value, `powerOf2AlignmentSize`
 * Params:
 *   n = value to be roundup
 *   powerOf2AlignmentSize = power of 2 modular value
 * Returns:
 *   roundup value
 */
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

/**
 * Converts string of base-64 characters into ubyte array
 * Params:
 *   validBase64Text = base-64 characters to be converted
 * Returns:
 *   ubyte[] if `validBase64Text` is a valid base-64 characters
 *   null/empty if `validBase64Text` is invalid
 */
ubyte[] bytesFromBase64s(scope const(char)[] validBase64Text) nothrow pure @safe
{
    NoDecodeInputRange!(validBase64Text, char) inputRange;
    ShortStringBuffer!ubyte result;
    if (parseBase64(inputRange, result) != NumericParsedKind.ok)
        return null;
    return result[].dup;
}

/**
 * Convert byte array to its base64 presentation
 * Params:
 *  bytes = bytes to be converted
 * Returns:
 *  array of base64 characters
 */
char[] bytesToBase64s(scope const(ubyte)[] bytes) nothrow pure @safe
{
    return cvtBytesBase64(bytes, Base64MappingChar.padding, false);
}

/**
 * Converts string of hex-digits into ubyte array
 * Params:
 *   validHexDigits = hex-digits to be converted
 * Returns:
 *   ubyte[] if `validHexDigits` is a valid hex-digits
 *   null/empty if `validHexDigits` is invalid
 */
ubyte[] bytesFromHexs(scope const(char)[] validHexDigits) nothrow pure @safe
{
    NoDecodeInputRange!(validHexDigits, char) inputRange;
    ShortStringBuffer!ubyte result;
    if (parseHexDigits(inputRange, result) != NumericParsedKind.ok)
        return null;
    return result[].dup;
}

/**
 * Convert byte array to its hex presentation
 * Params:
 *  bytes = bytes to be converted
 * Returns:
 *  array of hex characters
 */
char[] bytesToHexs(scope const(ubyte)[] bytes) nothrow pure @safe
{
    return cvtBytesHex(bytes, LetterCase.upper, false);
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

/**
 * Returns the caller function name
 */
string functionName(string name = __FUNCTION__) nothrow pure @safe
{
    return name;
}

/**
 * Checks and returns `value` within `min` and `max` inclusive
 * Params:
 *   value = a value to be checked
 *   min = inclusive minimum value
 *   max = inclusive maximum value
 * Returns:
 *   `min` if `value` is less than `min`
 *   `max` if `value` is greater than `max`
 *   otherwise `value`
 */
pragma(inline, true)
T limitRangeValue(T)(T value, T min, T max) nothrow pure @safe
{
    static if (__traits(compiles, T.init < T.init && T.init > T.init))
    {
        return value < min ? min : (value > max ? max : value);
    }
    else
        static assert(0, "Unsupport system for " ~ __FUNCTION__ ~ "." ~ T.stringof);
}

/**
 * Pads the left of string `value` with character `c` if `value.length` is shorter than `size`
 * Params:
 *   value = the string value to be checked and padded
 *   size = max length to be checked against value.length
 *          a positive value will do a left padding
 *          a negative value will do a right padding
 *   c = a character used for padding
 * Returns:
 *   a string with proper padded character(s)
 */
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
 * Returns the complete class-name of 'object' without template type if any. If `object` is null, returns "null"
 * Params:
 *   object = the object to get the class-name from
 */
string shortClassName(Object object) nothrow pure @safe
{
    return object is null ? "null" : shortenTypeName(typeid(object).name);
}

/**
 * Returns the complete aggregate-name of a class/struct without template type
 */
string shortTypeName(T)() nothrow @safe
if (is(T == class) || is(T == struct))
{
    return shortenTypeName(typeid(T).name);
}

/**
 * Strip out the template type if any and returns it
 * Params:
 *   fullName = the complete type name
 */
string shortenTypeName(string fullName) nothrow pure @safe
{
    import std.algorithm.iteration : filter;
    import std.array : join, split;
    import std.string : indexOf;

    return split(fullName, ".").filter!(e => e.indexOf('!') < 0).join(".");
}

/**
 * Returns FormatSpec!char with `f` format specifier
 */
FormatSpec!char simpleFloatFmt() nothrow pure @safe
{
    FormatSpec!char result;
    result.spec = 'f';
    return result;
}

/**
 * Returns FormatSpec!char with `d` format specifier
 * Params:
 *   width = optional width of formated string
 */
FormatSpec!char simpleIntegerFmt(int width = 0) nothrow pure @safe
{
    FormatSpec!char result;
    result.spec = 'd';
    result.width = width;
    return result;
}

/**
 * Initialize parameter `v` if `v` is null in thread safe manner using pass-in 'initiate' function
 * Params:
 *   v = variable to be initialized to object T if it is null
 *   initiate = a function that returns the newly created object as of T
 * Returns:
 *   parameter `v`
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

/**
 * Returns a string with length `count` with specified character `c`
 * Params:
 *   count = number of characters
 *   c = expected string of character
 */
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

/**
 * Converts an integral value into character output-range and returns its' output-range
 * Params:
 *   sink = character output-range
 *   n = an integral value to be converted
 *   paddingSize = optional padding length
 *   paddingChar = optional padding character; used only if paddingSize is not zero
 *   letterCase = specified upper-case or lower-case characters for radix 16 conversion
 * Returns:
 *   passed in paramter `sink`
 */
ref Writer toString(uint radix = 10, N, Writer)(return ref Writer sink, N n,
    const(ubyte) paddingSize = 0, const(char) paddingChar = '0',
    const(LetterCase) letterCase = LetterCase.upper) nothrow pure @safe
if (isIntegral!N && (radix == 2 || radix == 8 || radix == 10 || radix == 16))
{
    import std.ascii : lowerHexDigits, upperHexDigits=hexDigits, decimalDigits=digits;

    alias UN = Unqual!N;
    enum bufSize = 300;

    char[bufSize] bufDigits;
    size_t bufIndex = bufSize;
    const isNeg = radix == 10 && n < 0;

    static if (radix == 10)
    {
        UN un = isNeg ? cast(N)-n : n;
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

    if (paddingSize)
    {
        size_t cn = isNeg ? (bufSize - bufIndex + 1) : (bufSize - bufIndex);
        while (paddingSize > cn)
        {
            bufDigits[--bufIndex] = paddingChar;
            cn++;
        }
    }

    if (isNeg)
        bufDigits[--bufIndex] = '-';

    put(sink, bufDigits[bufIndex..bufSize]);
    return sink;
}

/**
 * Boxer type to have indicator that its' value has been set or not-set regardless of if the setting value
 * is a default one
 */
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

    C opCast(C: bool)() const @nogc pure
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

    /**
     * Resets this instance to initial state
     */
    ref typeof(this) reset() return
    {
        if (_inited)
        {
            _value = T.init;
            _inited = false;
        }
        return this;
    }


    /**
     * Indicates if value had been set or not-set
     */
    @property bool inited() const @nogc pure
    {
        return _inited;
    }

    /**
     * Returns current holding value
     */
    @property inout(T) value() inout pure
    {
        return _value;
    }

    alias value this;

private:
    T _value;
    bool _inited;
}

/**
 * Wrapper for Mutex to handle locking & unlocking automatically using
 * Resource Acquisition Is Initialization or RAII technique
 */
struct RAIIMutex
{
@nogc nothrow @safe:

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    /**
     * Get holding of `mutex` and call `lock` function
     */
    this(Mutex mutex)
    {
        this._lockedCounter = 0;
        this._mutex = mutex;
        lock();
    }

    /**
     * Release holding of `mutex` and call `unlock` function if is `isLocked`
     */
    ~this()
    {
        if (isLocked)
            unlock();
        _mutex = null;
    }

    /**
     * Increase `lockedCounter` and call `mutex.lock_nothrow` if `lockedCounter` = 1
     * You must call its corresponding `unlock` to release the mutex
     */
    void lock()
    {
        if (_lockedCounter++ == 0 && _mutex !is null)
            _mutex.lock_nothrow();
    }

    /**
     * Decrease `lockedCounter` and call `mutex.unlock_nothrow` if `lockedCounter` = 0
     */
    void unlock()
    {
        if (--_lockedCounter == 0 && _mutex !is null)
            _mutex.unlock_nothrow();
    }

    /**
     * Returns true if `lockedCounter` is greater than zero
     */
    pragma(inline, true)
    @property bool isLocked() const pure
    {
        return _lockedCounter > 0;
    }

    /**
     * Returns counter of function `lock` had been called
     */
    @property int lockedCounter() const pure
    {
        return _lockedCounter;
    }

private:
    Mutex _mutex;
    int _lockedCounter;
}

struct VersionString
{
    import std.array : join, split;
    import std.algorithm.comparison : min;
    import std.algorithm.iteration : map;
    import std.conv : to;
    import std.string : strip;
    import pham.utl.utl_array : ShortStringBuffer;
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;

nothrow @safe:

public:
    enum maxPartLength = 4;
    enum stopPartValue = uint.max; // A way to signal logical order stopped on certain version index/position part

    static struct Parti
    {
    nothrow @safe:

    public:
        this(scope const(uint)[] parti) @nogc pure
        {
            const len = min(parti.length, maxPartLength);
            this._length = cast(ubyte)len;
            this.data[0..len] = parti[0..len];
        }

        this(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) @nogc pure
        {
            this._length = 4;
            this.data[0] = major;
            this.data[1] = minor;
            this.data[2] = release;
            this.data[3] = build;
        }

        this(const(uint) major, const(uint) minor) @nogc pure
        {
            this._length = 2;
            this.data[0] = major;
            this.data[1] = minor;
        }

        int opCmp(scope const(Parti) rhs) const @nogc pure
        {
            const stopLHS = this.stopLength;
            const stopRHS = rhs.stopLength;
            const stopLen = stopRHS > stopLHS ? stopLHS : stopRHS;

            const cmpLHS = this._length > stopLen ? stopLen : this._length;
            const cmpRHS = rhs._length > stopLen ? stopLen : rhs._length;
            const cmpLen = cmpRHS > cmpLHS ? cmpLHS : cmpRHS;

            foreach (i; 0..cmpLen)
            {
                const result = cmp(this.data[i], rhs.data[i]);
                if (result != 0)
                    return result;
            }

            return cmp(cmpLHS, cmpRHS);
        }

        bool opEquals(scope const(Parti) rhs) const @nogc pure
        {
            return opCmp(rhs) == 0;
        }

        pragma(inline, true)
        size_t stopLength() const @nogc pure
        {
            foreach (i; 0..maxPartLength)
            {
                if (data[i] == stopPartValue)
                    return i;
            }
            return maxPartLength;
        }

        string toString() const pure
        {
            return _length ? data[0.._length].map!(v => to!string(v)).join(".") : null;
        }

        @property bool empty() const @nogc pure
        {
            return _length == 0;
        }

        @property size_t length() const @nogc pure
        {
            return _length;
        }

        @property size_t length(const(size_t) newLength) @nogc pure
        {
            _length = cast(ubyte)min(newLength, maxPartLength);
            return _length;
        }

    public:
        uint[maxPartLength] data;

    private:
        ubyte _length;
    }

    static struct Parts
    {
    nothrow @safe:

    public:
        this(scope const(uint)[] parti) pure
        {
            const len = min(parti.length, maxPartLength);
            ShortStringBuffer!char tempBuffer;
            this._length = cast(ubyte)len;
            foreach (i; 0..len)
                this.data[i] = .toString(tempBuffer.clear(), parti[i]).toString();
        }

        bool opEquals(scope const(Parts) rhs) const @nogc pure
        {
            const sameLength = this._length == rhs._length;
            if (sameLength)
            {
                foreach (i; 0..this._length)
                {
                    if (this.data[i] != rhs.data[i])
                        return false;
                }
            }
            return sameLength;
        }

        static Parts parse(string versionString) pure
        {
            static immutable uint[] n = [];
            return versionString.length != 0 ? Parts(split(versionString, ".")) : Parts(n);
        }

        /**
         * Convert version part strings into their integral presentation.
         * If a string is not able to be converted because of empty or invalid character(s),
         * the value will be substituted with zero
         */
        Parti toParti() const @nogc pure scope
        {
            Parti result;
            result._length = _length;
            foreach (i; 0.._length)
            {
                if (parseIntegral(data[i], result.data[i]) != NumericParsedKind.ok)
                    result.data[i] = 0;
            }
            return result;
        }

        string toString() const pure
        {
            return _length ? data[0.._length].join(".") : null;
        }

        @property bool empty() const @nogc pure
        {
            return _length == 0;
        }

        @property size_t length() const @nogc pure
        {
            return _length;
        }

        @property size_t length(const(size_t) newLength) @nogc pure
        {
            _length = cast(ubyte)min(newLength, maxPartLength);
            return _length;
        }

    public:
        string[maxPartLength] data;

    private:
        this(string[] parts) pure
        {
            const len = min(parts.length, maxPartLength);
            this._length = cast(ubyte)len;
            foreach (i; 0..len)
                this.data[i] = parts[i].strip();
        }

    private:
        ubyte _length;
    }

public:
    this(string versionString) pure
    {
        this.parts = Parts.parse(versionString);
    }

    this(scope const(uint)[] parti) pure
    {
        this.parts = Parts(parti);
    }

    this(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) pure
    {
        this([major, minor, release, build]);
    }

    this(const(uint) major, const(uint) minor) pure
    {
        this([major, minor]);
    }

    int opCmp(scope const(VersionString) rhs) const @nogc pure
    {
        return opCmp(rhs.parts.toParti());
    }

    int opCmp(string rhs) const pure
    {
        auto rhsVersion = VersionString(rhs);
        return opCmp(rhsVersion.parts.toParti());
    }

    int opCmp(scope const(uint)[] rhs) const @nogc pure
    {
        return opCmp(Parti(rhs));
    }

    int opCmp(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) const @nogc pure
    {
        return opCmp(Parti(major, minor, release, build));
    }

    int opCmp(const(uint) major, const(uint) minor) const @nogc pure
    {
        return opCmp(Parti(major, minor));
    }

    int opCmp(scope const(Parti) rhs) const @nogc pure
    {
        return parts.toParti().opCmp(rhs);
    }

    bool opEquals(scope const(VersionString) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(string rhs) const pure
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(scope const(uint)[] rhs) const @nogc pure
    {
        return opCmp(Parti(rhs)) == 0;
    }

    bool opEquals(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) const @nogc pure
    {
        return opCmp(Parti(major, minor, release, build)) == 0;
    }

    bool opEquals(const(uint) major, const(uint) minor) const @nogc pure
    {
        return opCmp(Parti(major, minor)) == 0;
    }

    string toString() const pure
    {
        return parts.toString();
    }

    @property bool empty() const @nogc pure
    {
        return parts.empty;
    }

public:
    Parts parts;
}


// Any below codes are private
private:

version (unittest)
{
    class TestClassName
    {
        string testFN() nothrow @safe
        {
            return functionName();
        }
    }

    class TestClassTemplate(T) {}

    struct TestStructName
    {
        string testFN() nothrow @safe
        {
            return functionName();
        }
    }

    string testFN() nothrow @safe
    {
        return functionName();
    }
}

unittest // alignRoundup
{
    assert(alignRoundup(0, 4) == 0);
    assert(alignRoundup(1, 4) == 4);
    assert(alignRoundup(4, 4) == 4);

    assert(alignRoundup(1, 16) == 16);
    assert(alignRoundup(15, 16) == 16);
    assert(alignRoundup(16, 16) == 16);
}

nothrow @safe unittest // bytesFromHexs & bytesToHexs
{
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
    r = bytesFromHexs("FFXY");
    assert(r == []);

    enum testHexs = "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443";
    auto bytes = bytesFromHexs(testHexs);
    assert(bytesToHexs(bytes) == testHexs);
}

nothrow @safe unittest // bytesFromBase64s
{
    import std.string : representation;

    assert(bytesFromBase64s("QUIx") == "AB1".representation());
}

nothrow @safe unittest // className
{
    auto c1 = new TestClassName();
    assert(className(c1) == "pham.utl.utl_object.TestClassName");

    auto c2 = new TestClassTemplate!int();
    assert(className(c2) == "pham.utl.utl_object.TestClassTemplate!int.TestClassTemplate");
}

nothrow @safe unittest // functionName
{
    auto c1 = new TestClassName();
    assert(c1.testFN() == "pham.utl.utl_object.TestClassName.testFN", c1.testFN());

    TestStructName s1;
    assert(s1.testFN() == "pham.utl.utl_object.TestStructName.testFN", s1.testFN());

    assert(testFN() == "pham.utl.utl_object.testFN", testFN());
}

nothrow @safe unittest // limitRangeValue
{
    assert(limitRangeValue(0, 0, 101) == 0);
    assert(limitRangeValue(101, 0, 101) == 101);
    assert(limitRangeValue(1, 0, 101) == 1);
    assert(limitRangeValue(-1, 0, 101) == 0);
    assert(limitRangeValue(102, 0, 101) == 101);
}

nothrow @safe unittest // pad
{
    assert(pad("", 2, ' ') == "  ");
    assert(pad("12", 2, ' ') == "12");
    assert(pad("12", 3, ' ') == " 12");
    assert(pad("12", -3, ' ') == "12 ");
}

nothrow @safe unittest // shortClassName
{
    auto c1 = new TestClassName();
    assert(shortClassName(c1) == "pham.utl.utl_object.TestClassName");

    auto c2 = new TestClassTemplate!int();
    assert(shortClassName(c2) == "pham.utl.utl_object.TestClassTemplate");
}

nothrow @safe unittest // shortTypeName
{
    assert(shortTypeName!TestClassName() == "pham.utl.utl_object.TestClassName", shortTypeName!TestClassName());
    assert(shortTypeName!(TestClassTemplate!int)() == "pham.utl.utl_object.TestClassTemplate", shortTypeName!(TestClassTemplate!int)());
    assert(shortTypeName!TestStructName() == "pham.utl.utl_object.TestStructName", shortTypeName!TestStructName());
}

unittest // singleton
{
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
    assert(stringOfChar(4, ' ') == "    ");
    assert(stringOfChar(0, ' ').length == 0);
}

@safe unittest // toString
{
    import std.array : Appender;
    import std.conv : to;

    void testCheck(uint radix = 10, N)(N n, const(ubyte) pad, string expected,
        uint line = __LINE__)
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

unittest // InitializedValue
{
    InitializedValue!int n;
    assert(!n);
    assert(!n.inited);

    n = 0;
    assert(n);
    assert(n.inited);
    assert(n == 0);

    InitializedValue!TestClassName c;
    assert(!c);
    assert(!c.inited);

    c = null;
    assert(!c);
    assert(c.inited);

    c = new TestClassName();
    assert(c);
    assert(c.inited);
    assert(c !is null);
}

unittest // RAIIMutex
{
    auto mutex = new Mutex();

    {
        auto locker = RAIIMutex(mutex);
        assert(locker.isLocked);
        assert(locker.lockedCounter == 1);

        locker.lock();
        assert(locker.isLocked);
        assert(locker.lockedCounter == 2);

        locker.unlock();
        assert(locker.isLocked);
        assert(locker.lockedCounter == 1);
    }

    destroy(mutex);
}

nothrow @safe unittest // VersionString
{
    import std.conv : to;

    const v1Str = "2.2.3.4";
    const v1 = VersionString(v1Str);
    assert(v1.parts.data[0] == "2");
    assert(v1.parts.data[1] == "2");
    assert(v1.parts.data[2] == "3");
    assert(v1.parts.data[3] == "4");
    assert(v1.toString() == v1Str);
    assert(v1 == VersionString(v1Str));
    assert(v1 == v1Str);

    const v2Str = "2.2.0.0";
    const v2 = VersionString(v2Str);
    assert(v2.parts.data[0] == "2");
    assert(v2.parts.data[1] == "2");
    assert(v2.parts.data[2] == "0");
    assert(v2.parts.data[3] == "0");
    assert(v2.toString() == v2Str);
    assert(v2 == v2Str);
    assert(v2 == VersionString(v2Str));

    assert(v1 > v2);

    const v3 = VersionString(2, VersionString.stopPartValue, 2, 0);
    assert(v3.parts.data[0] == "2");
    assert(v3.parts.data[1] == to!string(VersionString.stopPartValue));
    assert(v3.parts.data[2] == "2");
    assert(v3.parts.data[3] == "0");
    assert(v1 == v3);
    assert(v2 == v3);

    const v4Str = "4.4.4.4";
    const v4 = VersionString(v4Str);
    assert(v4.parts.data[0] == "4");
    assert(v4.parts.data[1] == "4");
    assert(v4.parts.data[2] == "4");
    assert(v4.parts.data[3] == "4");
    assert(v3 < v4);

    const vbStr = "1.2";
    const vb = VersionString(vbStr);
    assert(vb.parts.data[0] == "1");
    assert(vb.parts.data[1] == "2");
    assert(vb.parts.data[2].length == 0);
    assert(vb.parts.data[3].length == 0);
    assert(vb.toString() == vbStr);

    auto vNull = VersionString("");
    assert(vNull.toString() == "");
    assert(vNull < "1.2.3.4");
    assert("1.2.3.4" > vNull);
}
