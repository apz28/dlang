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
import std.exception : assumeWontThrow;
import std.format : FormatSpec;
import std.math : isPowerOf2;
import std.range.primitives : put;
import std.traits : isArray, isAssociativeArray, isFloatingPoint, isIntegral, isPointer,
    isSomeChar, isSomeString, isUnsigned, Unqual;

version (TraceInvalidMemoryOp) import pham.utl.test;

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
    import pham.utl.numeric_parser : NumericParsedKind, parseBase64;
    import pham.utl.utf8 : NoDecodeInputRange, ShortStringBuffer;

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
    import pham.utl.numeric_parser : Base64MappingChar, cvtBytesBase64;

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
    import pham.utl.numeric_parser : NumericParsedKind, parseHexDigits;
    import pham.utl.utf8 : NoDecodeInputRange, ShortStringBuffer;

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
    import pham.utl.numeric_parser : cvtBytesHex;
    
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
 * Compares and returns logical order of integer type values
 * Params:
 *   lhs = left hand side of float value
 *   rhs = right hand side of float value
 * Retruns:
 *   -1 if `lhs` is less than `rhs`
 *   1 if `lhs` is greater than `rhs`
 *   0 otherwise
 */
pragma(inline, true)
int cmpInteger(T)(const(T) lhs, const(T) rhs) @nogc nothrow pure @safe
if (isIntegral!T)
{
    return (lhs > rhs) - (lhs < rhs);
}

/**
 * Compares and returns logical order of float type values
 * Params:
 *   lhs = left hand side of float value
 *   rhs = right hand side of float value
 * Retruns:
 *   float.nan if either `lhs` or `rhs` is a NaN value
 *   -1 if `lhs` is less than `rhs`
 *   1 if `lhs` is greater than `rhs`
 *   0 otherwise
 */
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

/**
 * Returns current computer-name of running process
 */
string currentComputerName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetComputerNameW;
        import std.conv : to;

        wchar[1000] result = void;
        uint len = result.length - 1;
        if (GetComputerNameW(&result[0], &len))
            return assumeWontThrow(to!string(result[0..len]));
        else
            return null;
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : gethostname;
        import std.conv : to;

        char[1000] result = void;
        uint len = result.length - 1;
        if (gethostname(&result[0], len) == 0)
            return assumeWontThrow(to!string(result.ptr));
        else
            return null;
    }
    else
    {
        pragma(msg, "currentComputerName() not supported");
        return null;
    }
}

/**
 * Returns current process-id of running process
 */
uint currentProcessId() nothrow @safe
{
    import std.process : thisProcessID;

    return thisProcessID;
}

/**
 * Returns current process-name of running process
 */
string currentProcessName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetModuleFileNameW;
        import std.conv : to;

        wchar[1000] result = void;
        const len = GetModuleFileNameW(null, &result[0], result.length - 1);
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
        return null;
    }
}

/**
 * Returns current os-account-name of running process
 */
string currentUserName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetUserNameW;
        import std.conv : to;

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
        import std.conv : to;

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
        static assert(0, "T must be a type with comparison operators '<' and '>'");
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
 * Compares and returns none-zero if both values are same sign
 * Params:
 *   lhs = left hand side of integral value
 *   rhs = right hand side of integral value
 * Retruns:
 *   -1 if `lhs` and `rhs` are both negative
 *   1 if `lhs` and `rhs` are both positive
 *   0 otherwise
 */
pragma(inline, true)
int sameSign(LHS, RHS)(const(LHS) lhs, const(RHS) rhs) @nogc nothrow pure @safe
if (isIntegral!LHS && isIntegral!RHS)
{
    const lhsP = lhs >= 0;
    const rhsP = rhs >= 0;
    
    return lhsP && rhsP ? 1 : (!lhsP && !rhsP ? -1 : 0);
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
 * Generic interface to implement disposable class
 * Sample object implementation of this interface, `DisposableObject`
 */
interface IDisposable
{
nothrow @safe:

    /**
     * The actual function to perform disposing logic
     * Params:
     *   disposing = indicate if it is called from `dispose` or object destructor
     *               true = called from `dispose`
     *               false = called from object destructor
     */
    void disposal(bool disposing);

    /*
     * Should just make call to `disposal` with parameter, `disposing` = true
     */
    void dispose();
}

/**
 * State of disposable class
 */
enum DisposableState : ubyte
{
    none,         /// dispose or destructor has not been called
    disposing,    /// in disposing state
    disposed,     /// already disposed
    destructing,  /// in destructing state
    destructed,   /// already destructed
}

/**
 * An abstract class to implement `IDisposable` interface
 */
abstract class DisposableObject : IDisposable
{
nothrow @safe:

public:
    /**
     * Implement IDisposable.disposal
     */
    final override void disposal(bool disposing)
    {
        if ((_disposingState == DisposableState.none) || (!disposing && _disposingState == DisposableState.disposed))
        {
            _disposingState = disposing ? DisposableState.disposing : DisposableState.destructing;
            doDispose(disposing);
            _disposingState = disposing ? DisposableState.disposed : DisposableState.destructed;
        }
    }

    /**
     * Implement IDisposable.dispose
     * Will do nothing if called more than one
     */
    final override void dispose()
    {
        disposal(true);
    }

    /**
     * Returns current disposing state of current object
     */
    @property final DisposableState disposingState() const @nogc pure
    {
        return _disposingState;
    }

protected:
    /**
     * Abstract function of this class to perform disposing logic
     */
    abstract void doDispose(bool disposing);

private:
    DisposableState _disposingState;
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
    @disable this();
    @disable this(ref typeof(this));
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
    import std.algorithm.iteration;
    import std.conv : to;
    import std.string : strip;
    import pham.utl.numeric_parser : NumericParsedKind, parseIntegral;
    import pham.utl.utf8 : ShortStringBuffer;

nothrow @safe:

public:
    enum maxPartLength = 4;

    static struct Parti
    {
    nothrow @safe:

        uint[maxPartLength] data;
        size_t length;

        int opCmp(scope const(Parti) rhs) const @nogc pure
        {
            const len = rhs.length > this.length ? this.length : rhs.length;
            foreach (i; 0..len)
            {
                const result = cmpInteger(data[i], rhs.data[i]);
                if (result != 0)
                    return result;
            }
            return cmpInteger(this.length, rhs.length);
        }

        bool opEquals(scope const(Parti) rhs) const @nogc pure
        {
            return opCmp(rhs) == 0;
        }

        static Parti parti(scope const(uint)[] parti) @nogc pure
        {
            Parti result;
            result.length = parti.length > maxPartLength ? maxPartLength : parti.length;
            if (parti.length > 0)
                result.data[0] = parti[0];
            if (parti.length > 1)
                result.data[1] = parti[1];
            if (parti.length > 2)
                result.data[2] = parti[2];
            if (parti.length > 3)
                result.data[3] = parti[3];
            return result;
        }

        static Parti parti(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) @nogc pure
        {
            Parti result;
            result.length = 4;
            result.data[0] = major;
            result.data[1] = minor;
            result.data[2] = release;
            result.data[3] = build;
            return result;
        }

        static Parti parti(const(uint) major, const(uint) minor) @nogc pure
        {
            Parti result;
            result.length = 2;
            result.data[0] = major;
            result.data[1] = minor;
            return result;
        }

        string toString() const pure
        {
            return empty ? null : data[0..length].map!(v => to!string(v)).join(".");
        }

        @property bool empty() const @nogc pure
        {
            return length == 0;
        }
    }

    static struct Parts
    {
    nothrow @safe:

        string[maxPartLength] data;
        size_t length;

        bool opEquals(scope const(Parts) rhs) const @nogc pure
        {
            const sameLength = this.length == rhs.length;
            if (sameLength)
            {
                foreach (i; 0..this.length)
                {
                    if (data[i] != rhs.data[i])
                        return false;
                }
            }
            return sameLength;
        }

        string toString() const pure
        {
            return empty ? null : data[0..length].join(".");
        }

        @property bool empty() const @nogc pure
        {
            return length == 0;
        }
    }

public:
    this(string versionString) pure
    {
        this.parts = parse(versionString);
    }

    this(scope const(uint)[] parts) pure
    {
        ShortStringBuffer!char tempBuffer;
        this.parts.length = parts.length > maxPartLength ? maxPartLength : parts.length;
        if (parts.length > 0)
            this.parts.data[0] = .toString(tempBuffer.clear(), parts[0]).toString();
        if (parts.length > 1)
            this.parts.data[1] = .toString(tempBuffer.clear(), parts[1]).toString();
        if (parts.length > 2)
            this.parts.data[2] = .toString(tempBuffer.clear(), parts[2]).toString();
        if (parts.length > 3)
            this.parts.data[3] = .toString(tempBuffer.clear(), parts[3]).toString();
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
        return opCmp(toParti(rhs.parts));
    }

    int opCmp(string rhs) const pure
    {
        return opCmp(toParti(VersionString(rhs).parts));
    }

    int opCmp(scope const(uint)[] rhs) const @nogc pure
    {
        return opCmp(Parti.parti(rhs));
    }

    int opCmp(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) const @nogc pure
    {
        return opCmp(Parti.parti(major, minor, release, build));
    }

    int opCmp(const(uint) major, const(uint) minor) const @nogc pure
    {
        return opCmp(Parti.parti(major, minor));
    }

    int opCmp(scope const(Parti) rhs) const @nogc pure
    {
        return toParti(parts).opCmp(rhs);
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
        return opCmp(Parti.parti(rhs)) == 0;
    }

    bool opEquals(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) const @nogc pure
    {
        return opCmp(Parti.parti(major, minor, release, build)) == 0;
    }

    bool opEquals(const(uint) major, const(uint) minor) const @nogc pure
    {
        return opCmp(Parti.parti(major, minor)) == 0;
    }

    static Parts parse(string versionString) pure
    {
        Parts result;
        if (versionString.length != 0)
        {
            auto versions = split(versionString, ".");
            if (versions.length > 0)
            {
                result.data[0] = versions[0].strip();
                result.length++;
            }
            if (versions.length > 1)
            {
                result.data[1] = versions[1].strip();
                result.length++;
            }
            if (versions.length > 2)
            {
                result.data[2] = versions[2].strip();
                result.length++;
            }
            if (versions.length > 3)
            {
                result.data[3] = versions[3].strip();
                result.length++;
            }
        }
        return result;
    }

    static Parti toParti(scope const(Parts) parts) @nogc pure
    in
    {
        assert(parts.length <= maxPartLength);
    }
    do
    {
        Parti result;
        result.length = parts.length;
        foreach (i; 0..parts.length)
        {
            if (parseIntegral(parts.data[i], result.data[i]) != NumericParsedKind.ok)
                result.data[i] = 0;
        }
        return result;
    }

    string toString() const pure
    {
        return parts.toString();
    }

    @property bool empty() const @nogc pure
    {
        return parts.length == 0;
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
    r = bytesFromHexs("FFXY");
    assert(r == []);

    enum testHexs = "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443";
    auto bytes = bytesFromHexs(testHexs);
    assert(bytesToHexs(bytes) == testHexs);
}

nothrow @safe unittest // bytesFromBase64s
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.bytesFromBase64s");

    assert(bytesFromBase64s("QUIx") == "AB1".representation());
}

nothrow @safe unittest // className
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.className");

    auto c1 = new TestClassName();
    assert(className(c1) == "pham.utl.object.TestClassName");

    auto c2 = new TestClassTemplate!int();
    assert(className(c2) == "pham.utl.object.TestClassTemplate!int.TestClassTemplate");
}

nothrow @safe unittest // cmpFloat
{
    import std.math : isNaN;
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.cmpFloat");

    assert(cmpFloat(0.0, 0.0) == 0);
    assert(cmpFloat(1.0, 2.0) == -1);
    assert(cmpFloat(1.0, 1.0) == 0);
    assert(cmpFloat(2.0, 1.0) == 1);
    assert(cmpFloat(-double.max, -double.max) == 0);
    assert(cmpFloat(double.max, double.max) == 0);
    assert(cmpFloat(-double.max, double.max) == -1);
    assert(cmpFloat(double.max, -double.max) == 1);
    assert(isNaN(cmpFloat(double.nan, 2.0)));
    assert(isNaN(cmpFloat(1.0, double.nan)));
    assert(isNaN(cmpFloat(double.nan, double.nan)));
}

nothrow @safe unittest // cmpInteger
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.cmpInteger");

    assert(cmpInteger(0, 0) == 0);
    assert(cmpInteger(1, 2) == -1);
    assert(cmpInteger(1, 1) == 0);
    assert(cmpInteger(2, 1) == 1);
    assert(cmpInteger(int.min, int.min) == 0);
    assert(cmpInteger(int.max, int.max) == 0);
    assert(cmpInteger(int.min, int.max) == -1);
    assert(cmpInteger(int.max, int.min) == 1);
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

nothrow @safe unittest // functionName
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.functionName");

    auto c1 = new TestClassName();
    assert(c1.testFN() == "pham.utl.object.TestClassName.testFN", c1.testFN());

    TestStructName s1;
    assert(s1.testFN() == "pham.utl.object.TestStructName.testFN", s1.testFN());

    assert(testFN() == "pham.utl.object.testFN", testFN());
}

nothrow @safe unittest // limitRangeValue
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.limitRangeValue");

    assert(limitRangeValue(0, 0, 101) == 0);
    assert(limitRangeValue(101, 0, 101) == 101);
    assert(limitRangeValue(1, 0, 101) == 1);
    assert(limitRangeValue(-1, 0, 101) == 0);
    assert(limitRangeValue(102, 0, 101) == 101);
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

nothrow @safe unittest // sameSign
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.sameSign");

    assert(sameSign(0, 0) == 1);
    assert(sameSign(1, 0) == 1);
    assert(sameSign(0, 1) == 1);
    assert(sameSign(3, 1) == 1);
    
    assert(sameSign(-1, -100) == -1);
    
    assert(sameSign(-1, 1) == 0);
    assert(sameSign(-10, 0) == 0);
    
    assert(sameSign(byte.min, byte.max) == 0);
    assert(sameSign(byte.min, int.max) == 0);
    assert(sameSign(byte.max, int.max) == 1);
    assert(sameSign(byte.min, int.min) == -1);
}

nothrow @safe unittest // shortClassName
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.shortClassName");

    auto c1 = new TestClassName();
    assert(shortClassName(c1) == "pham.utl.object.TestClassName");

    auto c2 = new TestClassTemplate!int();
    assert(shortClassName(c2) == "pham.utl.object.TestClassTemplate");
}

nothrow @safe unittest // shortTypeName
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.shortTypeName");

    assert(shortTypeName!TestClassName() == "pham.utl.object.TestClassName", shortTypeName!TestClassName());
    assert(shortTypeName!(TestClassTemplate!int)() == "pham.utl.object.TestClassTemplate", shortTypeName!(TestClassTemplate!int)());
    assert(shortTypeName!TestStructName() == "pham.utl.object.TestStructName", shortTypeName!TestStructName());
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

@safe unittest // toString
{
    import std.array : Appender;
    import std.conv : to;
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

unittest // DisposableObject
{
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.DisposableObject");

    static int stateCounter;

    static class TestDisposableObject : DisposableObject
    {
    public:
        ~this()
        {
            disposal(false);
            assert(disposingState == DisposableState.destructed);
        }

    protected:
        override void doDispose(bool disposing)
        {
            if (disposing)
                assert(disposingState == DisposableState.disposing);
            else
                assert(disposingState == DisposableState.destructing);

            stateCounter++;
        }
    }

    auto c = new TestDisposableObject();
    assert(c.disposingState == DisposableState.none);

    c.dispose();
    assert(c.disposingState == DisposableState.disposed);
    assert(stateCounter == 1);
    c.dispose(); // Do nothing if call second time (or subsequece dispose calls)
    assert(c.disposingState == DisposableState.disposed);
    assert(stateCounter == 1);

    destroy(c);
    assert(stateCounter == 2);
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
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.RAIIMutex");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.object.VersionString");

    const v1Str = "1.2.3.4";
    const v1 = VersionString(v1Str);
    assert(v1.parts.data[0] == "1");
    assert(v1.parts.data[1] == "2");
    assert(v1.parts.data[2] == "3");
    assert(v1.parts.data[3] == "4");
    assert(v1.toString() == v1Str);

    const v2Str = "1.2.0.0";
    const v2 = VersionString(v2Str);
    assert(v2.parts.data[0] == "1");
    assert(v2.parts.data[1] == "2");
    assert(v2.parts.data[2] == "0");
    assert(v2.parts.data[3] == "0");
    assert(v2.toString() == v2Str);

    assert(v1 > v2);
    assert(v1 == VersionString(v1Str));
    assert(v1 == v1Str);
    assert(v2 == v2Str);
    assert(v2 == VersionString(v2Str));

    auto vNull = VersionString("");
    assert(vNull.toString() == "");
    assert(vNull < "1.2.3.4");
    assert("1.2.3.4" > vNull);
}
