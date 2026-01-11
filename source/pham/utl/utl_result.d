/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2022 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_result;

import std.conv : to;
import std.math.traits : isNaN;
import std.traits : fullyQualifiedName, isFloatingPoint, isIntegral, isScalarType;

@safe:

/**
 * Appending a 'line' to 'lines',
 * using std.ascii.newline as separator if lines is not empty
 * Params:
 *  lines = destination string
 *  line = source string
 * Returns:
 *  a string, 'lines'
 */
string addLine(ref string lines, string line) nothrow pure
{
    import std.ascii : newline;

    if (lines.length == 0)
        lines = line;
    else
        lines = lines ~ newline ~ line;
    return lines;
}

/**
 * Appending a 'line' to 'lines' only if 'line' is not empty,
 * using std.ascii.newline as separator if lines is not empty
 * Params:
 *  lines = destination string
 *  line = source string
 * Returns:
 *  a string, 'lines'
 */
string addLineIf(ref string lines, string line) nothrow pure
{
    if (line.length)
        return addLine(lines, line);
    else
        return lines;
}

/**
 * Compares and returns logical order of float type values
 * Params:
 *   lhs = left hand side of float value
 *   rhs = right hand side of float value
 * Returns:
 *   state = float.nan if either lhs or rhs is an NaN number
 *           or float.nan if either lhs or rhs is an infinity number and same sign
 *   state = -1 if lhs is less than rhs
 *   state = 0 if lhs is equal rhs
 *   state = 1 if lhs is greater than rhs
 */
float cmp(T)(const(T) lhs, const(T) rhs) @nogc nothrow pure
if (isFloatingPoint!T)
{
    import std.math : isInfinity, sgn;

    // One or both are nan
    if (isNaN(lhs) || isNaN(rhs))
        return float.nan;

    // One or both are infinity
    const lhsInf = isInfinity(lhs);
    const rhsInf = isInfinity(rhs);
    if (lhsInf || rhsInf)
    {
        const lhsSgn = sgn(lhs);
        const rhsSgn = sgn(rhs);
        // Same sign ?
        if (lhsSgn == rhsSgn)
            return lhsInf && rhsInf
                ? float.nan // Both are infinity
                : (lhsInf ? lhsSgn : (rhsInf ? rhsSgn : 0.0));
        else
            // Compare by sign bit
            return (lhsSgn > rhsSgn) - (lhsSgn < rhsSgn);
    }

    // This pattern for three-way comparison is better than conditional operators
    // See e.g. https://godbolt.org/z/3j4vh1
    return (lhs > rhs) - (lhs < rhs);
}

/**
 * Compares and returns logical order of integer type values
 * Params:
 *   lhs = left hand side of integer value
 *   rhs = right hand side of integer value
 * Retruns:
 *   -1 if lhs is less than rhs
 *   0 if lhs is equal rhs
 *   1 if lhs is greater than rhs
 */
pragma(inline, true)
int cmp(T)(const(T) lhs, const(T) rhs) @nogc nothrow pure
if (isIntegral!T)
{
    // This pattern for three-way comparison is better than conditional operators
    // See e.g. https://godbolt.org/z/3j4vh1
    return (lhs > rhs) - (lhs < rhs);
}

float cmp(T)(scope const(T)[] lhs, scope const(T)[] rhs) @nogc nothrow pure
if (isFloatingPoint!T)
{
    const len = lhs.length <= rhs.length ? lhs.length : rhs.length;
    foreach (const i; 0..len)
    {
        const r = cmp(lhs[i], rhs[i]);
        if (r != 0) // float.nan != 0 => true
            return r;
    }
    return cmp(lhs.length, rhs.length);
}

auto cmp(T)(scope const(T)[] lhs, scope const(T)[] rhs) @nogc nothrow pure @trusted
if (isScalarType!T && !isFloatingPoint!T)
{
    // Compute U as the implementation type for T
    static if (is(T == ubyte) || is(T == void) || is(T == bool))
        alias U = char;
    else static if (is(T == wchar))
        alias U = ushort;
    else static if (is(T == dchar))
        alias U = uint;
    else static if (is(T == ifloat))
        alias U = float;
    else static if (is(T == idouble))
        alias U = double;
    else static if (is(T == ireal))
        alias U = real;
    else
        alias U = T;

    static if (is(U == char))
    {
        import core.internal.string : dstrcmp;

        return dstrcmp(cast(const(char)[])lhs, cast(const(char)[])rhs);
    }
    else static if (!is(U == T))
    {
        // Reuse another implementation
        return cmp(cast(const(U)[])lhs, cast(const(U)[])rhs);
    }
    else
    {
        const len = lhs.length <= rhs.length ? lhs.length : rhs.length;

        version(BigEndian)
        static if (__traits(isUnsigned, T) ? !is(T == __vector) : is(T : P*, P))
        {
            if (!__ctfe)
            {
                import core.stdc.string : memcmp;

                const c = memcmp(lhs.ptr, rhs.ptr, len * T.sizeof);
                return c ? c : cmp(lhs.length, rhs.length);
            }
        }

        foreach (const i; 0..len)
        {
            static if (is(T : creal))
            {
                const a = lhs[i], b = rhs[i];
                auto r = cmp(a.re, b.re);
                if (!r)
                    r = cmp(a.im, b.im);
            }
            else
            {
                const r = cmp(lhs[i], rhs[i]);
            }
            if (r)
                return r;
        }
        return cmp(lhs.length, rhs.length);
    }
}

float cmp(T1, T2)(T1[] lhs, T2[] rhs)
if (!isScalarType!T1 && !isScalarType!T2)
{
    import core.internal.traits : Unqual;
    alias U1 = Unqual!T1;
    alias U2 = Unqual!T2;

    static if (is(U1 == void) && is(U2 == void))
    {
        static ref inout(ubyte) at(inout(void)[] r, size_t i) @trusted
        {
            return (cast(inout(ubyte)*)r.ptr)[i];
        }
    }
    else
    {
        static ref R at(R)(R[] r, size_t i) @trusted
        {
            return r.ptr[i];
        }
    }

    // All unsigned byte-wide types = > dstrcmp
    const len = lhs.length <= rhs.length ? lhs.length : rhs.length;
    foreach (const i; 0..len)
    {
        static if (__traits(compiles, cmp(at(lhs, i), at(rhs, i))))
        {
            const c = cmp(at(lhs, i), at(rhs, i));
            if (c != 0)
                return c;
        }
        else static if (__traits(compiles, at(lhs, i).opCmp(at(rhs, i))))
        {
            const c = at(lhs, i).opCmp(at(rhs, i));
            if (c != 0)
                return c;
        }
        else static if (__traits(compiles, at(lhs, i) < at(rhs, i)))
        {
            if (const result = (at(lhs, i) > at(rhs, i)) - (at(lhs, i) < at(rhs, i)))
                return result;
        }
        else
        {
            // TODO: fix this legacy bad behavior, see
            // https://issues.dlang.org/show_bug.cgi?id=17244
            static assert(is(U1 == U2));
            import core.stdc.string : memcmp;

            const c = (() @trusted => memcmp(&at(lhs, i), &at(rhs, i), U1.sizeof))();
            if (c != 0)
                return c;
        }
    }
    return cmp(lhs.length, rhs.length);
}

string errorCodeToString(I)(I errorCode) nothrow pure
if (isIntegral!I)
{
    return "0x" ~ to!string(errorCode, 16) ~ " (" ~ errorCode.to!string() ~ ")";
}

string genericErrorMessage(I)(string apiName, I errorCode) nothrow pure
if (isIntegral!I)
{
    return apiName ~ " - Error code: " ~ errorCodeToString(errorCode);
}

string getSystemErrorMessage(const(uint) errorCode) nothrow @trusted
in
{
    assert(errorCode != 0);
}
do
{
    version(Windows)
    {
        import core.sys.windows.winbase : FormatMessageW, FORMAT_MESSAGE_FROM_SYSTEM, FORMAT_MESSAGE_IGNORE_INSERTS;
        import core.sys.windows.winnt : LANG_NEUTRAL;

        wchar[1_000] buf = '\0';
        auto n = FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, errorCode, LANG_NEUTRAL, buf.ptr, buf.length, null);
        return n > 0 ? osWCharToString(buf[0..n]) : null;
    }
    else version(Posix)
    {
        import core.stdc.string : strlen, strerror_r;

        char[1_000] buf = '\0';
        const(char)* p;

        version(CRuntime_Glibc)
            p = strerror_r(errorCode, buf.ptr, buf.length);
        else
        {
            if (!strerror_r(errorCode, buf.ptr, buf.length))
                p = buf.ptr;
        }
        return p !is null ? osCharToString(p[0..p.strlen]) : null;
    }
    else
        static assert(0, "Unsupport system for " ~ __FUNCTION__);
}

pragma(inline, true)
uint lastSystemError() nothrow @trusted
{
    version(Windows)
    {
        import core.sys.windows.winbase : GetLastError;

        return GetLastError();
    }
    else version(Posix)
    {
        import core.stdc.errno : errno;

        return errno;
    }
    else
        static assert(0, "Unsupport system for " ~ __FUNCTION__);
}

uint lastSystemError(uint lastError) nothrow @trusted
{
    version(Windows)
    {
        import core.sys.windows.winbase : SetLastError;

        SetLastError(lastError);
        return lastError;
    }
    else version(Posix)
    {
        import core.stdc.errno : errno;

        errno = lastError;
        return lastError;
    }
    else
        static assert(0, "Unsupport system for " ~ __FUNCTION__);
}

ResultStatus lastSystemError(string apiName,
    string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
{
    auto code = lastSystemError();
    auto message = getSystemErrorMessage(code);
    return ResultStatus.error(code, message.length != 0 ? message : genericErrorMessage(apiName, code), funcName, file, line);
}

string osCharToString(scope const(char)[] v) nothrow pure
{
    auto length = v.length;
    while (length != 0 && v[length - 1] <= ' ')
        length--;
    return v[0..length].idup;
}

string osWCharToString(scope const(wchar)[] v) nothrow pure
{
    scope (failure) assert(0, "Assume nothrow failed");

    auto length = v.length;
    while (length != 0 && v[length - 1] <= ' ')
        length--;
    return v[0..length].to!string();
}

/**
 * Compares and returns none-zero if both values are same sign
 * Params:
 *   lhs = left hand side of integral value
 *   rhs = right hand side of integral value
 * Returns:
 *   -1 if `lhs` and `rhs` are both negative
 *   1 if `lhs` and `rhs` are both positive
 *   0 otherwise
 */
pragma(inline, true)
int sameSign(LHS, RHS)(const(LHS) lhs, const(RHS) rhs) @nogc nothrow pure
if (isIntegral!LHS && isIntegral!RHS)
{
    const lhsP = lhs >= 0;
    const rhsP = rhs >= 0;

    return lhsP && rhsP ? 1 : (!lhsP && !rhsP ? -1 : 0);
}

struct CmpResult
{
nothrow @safe:

public:
    enum unknownResult = float.nan;
    enum unknownResultInt = int.max;

public:
    this(float state) @nogc pure
    {
        this._state = isNaN(state)
            ? unknownResult
            : (state > 0 ? 1 : (state < 0 ? -1 : 0));
    }

    this(int state) @nogc pure
    {
        this._state = state == unknownResultInt
            ? unknownResult
            : (state > 0 ? 1 : (state < 0 ? -1 : 0));
    }

    /**
     * Construct logical order state of integral type values
     * Params:
     *   lhs = left hand side of integral value
     *   rhs = right hand side of integral value
     * Returns:
     *   state = -1 if lhs is less than rhs
     *   state = 0 if lhs is equal rhs
     *   state = 1 if lhs is greater than rhs
     */
    this(T)(const(T) lhs, const(T) rhs) @nogc pure
    if (isIntegral!T)
    {
        this._state = cmp(lhs, rhs);
    }


    /**
     * Construct logical order state of floating point type values
     * Params:
     *   lhs = left hand side of floating point value
     *   rhs = right hand side of floating point value
     * Returns:
     *   state = float.nan if either lhs or rhs is an NaN number
     *           or float.nan if either lhs or rhs is an infinity number and same sign
     *   state = -1 if lhs is less than rhs
     *   state = 0 if lhs is equal rhs
     *   state = 1 if lhs is greater than rhs
     */
    this(T)(const(T) lhs, const(T) rhs) @nogc pure
    if (isFloatingPoint!T)
    {
        this._state = cmp(lhs, rhs);
    }

    pragma(inline, true)
    C opCast(C: int)() const @nogc pure
    {
        return this.isValid ? cast(int)_state : unknownResultInt;
    }

    /**
     * Return true based on pivot value, pivotValue, and the state is valid
     */
    pragma(inline, true)
    bool isOp(string op)(const(int) pivotValue) const @nogc pure
    if (op == "==" || op == "!=" || op == ">" || op == ">=" || op == "<" || op == "<=")
    {
        static if (op == "==")
            return _state == pivotValue && isValid;
        else static if (op == "!=")
            return _state != pivotValue && isValid;
        else static if (op == ">")
            return _state > pivotValue && isValid;
        else static if (op == ">=")
            return _state >= pivotValue && isValid;
        else static if (op == "<")
            return _state < pivotValue && isValid;
        else static if (op == "<=")
            return _state <= pivotValue && isValid;
        else
            static assert(0);
    }

    static CmpResult unknown() @nogc pure
    {
        return CmpResult(unknownResult);
    }

    pragma(inline, true)
    @property bool isValid() const @nogc pure
    {
        return !isNaN(_state);
    }

    pragma(inline, true)
    @property float state() const @nogc pure
    {
        return _state;
    }

    alias this = state;

private:
    float _state = unknownResult;
}

/**
 * Simple aggregate to indicate if function result is an error or intended value
 */
struct ResultIf(T)
{
@safe:

public:
    this(T value, ResultStatus status) nothrow
    {
        this.value = value;
        this.status = status;
    }

    bool opCast(C: bool)() const @nogc nothrow pure scope
    {
        return isOK;
    }

    string getErrorString() const nothrow pure
    {
        return status.getErrorString();
    }

    /**
     * Create this result-type as error
     */
    pragma(inline, true)
    static typeof(this) error(uint errorCode, string errorMessage,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        return typeof(this)(T.init, ResultStatus.error(errorCode, errorMessage, funcName, file, line));
    }

    pragma(inline, true)
    static typeof(this) error(T value, uint errorCode, string errorMessage,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        return typeof(this)(value, ResultStatus.error(errorCode, errorMessage, funcName, file, line));
    }

    static typeof(this) systemError(string apiName, uint errorCode, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        return typeof(this)(T.init, ResultStatus.systemError(apiName, errorCode, postfixMessage, funcName, file, line));
    }

    static typeof(this) systemError(T value, string apiName, uint errorCode, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        return typeof(this)(value, ResultStatus.systemError(apiName, errorCode, postfixMessage, funcName, file, line));
    }

    /**
     * Create this result-type without error
     */
    pragma(inline, true)
    static typeof(this) ok(T value) nothrow
    {
        return typeof(this)(value, ResultStatus.ok());
    }

    pragma(inline, true)
    @property uint errorCode() const @nogc nothrow pure
    {
        return status.errorCode;
    }

    @property string errorMessage() const @nogc nothrow pure
    {
        return status.errorMessage;
    }

    /**
     * Returns true if there is error-code or error-message
     */
    pragma(inline, true)
    @property bool isError() const @nogc nothrow pure scope
    {
        return status.isError;
    }

    /**
     * Returns true if there is no error-code and error-message
     */
    pragma(inline, true)
    @property bool isOK() const @nogc nothrow pure scope
    {
        return status.isOK;
    }

public:
    T value;
    ResultStatus status = ResultStatus(ResultCode.uninitialized, null, null, null, 0);

    alias this = value;
}

enum ResultCode : int
{
    ok = 0,
    error = -1,
    unsupported = -2,
    uninitialized = -3,
}

deprecated("please use " ~ fullyQualifiedName!(ResultCode.ok))
enum resultOK = ResultCode.ok;
deprecated("please use " ~ fullyQualifiedName!(ResultCode.error))
enum resultError = ResultCode.error;
deprecated("please use " ~ fullyQualifiedName!(ResultCode.unsupported))
enum resultUnsupported = ResultCode.unsupported;
deprecated("please use " ~ fullyQualifiedName!(ResultCode.uninitialized))
enum resultUninitialized = ResultCode.uninitialized;

struct ResultStatus
{
@safe:

public:
    this(uint errorCode, string errorMessage,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @nogc nothrow pure
    {
        this.errorCode = errorCode;
        this.errorMessage = errorMessage;
        this.funcName = funcName;
        this.file = file;
        this.line = line;
    }

    bool opCast(C: bool)() const @nogc nothrow pure scope
    {
        return isOK;
    }

    ref typeof(this) addMessageIf(string errorLine) nothrow pure return
    {
        addLineIf(this.errorMessage, errorLine);
        return this;
    }

    int clone(ResultStatus source, const(int) resultCode) @nogc nothrow pure
    {
        this.errorCode = source.errorCode;
        this.errorMessage = source.errorMessage;
        this.funcName = source.funcName;
        this.file = source.file;
        this.line = source.line;
        return resultCode;
    }

    pragma(inline, true)
    static typeof(this) error(uint errorCode, string errorMessage,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @nogc nothrow pure
    {
        return typeof(this)(errorCode, errorMessage, funcName, file, line);
    }

    static typeof(this) systemError(string apiName, uint errorCode, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        typeof(this) result;
        result.setSystemError(apiName, errorCode, postfixMessage, funcName, file, line);
        return result;
    }

    static typeof(this) unsupportedError(uint errorCode, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        typeof(this) result;
        result.setUnsupportedError(errorCode, postfixMessage, funcName, file, line);
        return result;
    }

    string getErrorString() const nothrow pure
    {
        return errorMessage.length != 0
            ? errorMessage
            : (errorCode != 0 ? ("Error code: " ~ errorCodeToString(errorCode)) : null);
    }

    pragma(inline, true)
    static typeof(this) ok() @nogc nothrow pure
    {
        return typeof(this)(0, null, null, null, 0);
    }

    pragma(inline, true)
    int reset(const(int) resultCode = ResultCode.ok) @nogc nothrow pure
    {
        this.errorMessage = this.file = this.funcName = null;
        this.errorCode = this.line = 0;
        return resultCode;
    }

    int set(uint errorCode, string errorMessage, const(int) resultCode = ResultCode.error,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) @nogc nothrow pure
    {
        this.errorCode = errorCode;
        this.errorMessage = errorMessage;
        this.funcName = funcName;
        this.file = file;
        this.line = line;
        return resultCode;
    }

    int setError(uint errorCode, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        this.errorCode = errorCode;
        this.errorMessage = "Failed " ~ funcName ~ postfixMessage;
        this.funcName = funcName;
        this.file = file;
        this.line = line;
        this.addMessageIf(errorCode != 0 ? ("Error code: " ~ errorCodeToString(errorCode)) : null);
        return ResultCode.error;
    }

    int setSystemError(string apiName, uint errorCode, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        this.errorCode = errorCode;
        this.errorMessage = "Failed " ~ apiName ~ postfixMessage;
        this.funcName = funcName;
        this.file = file;
        this.line = line;
        this.addMessageIf(errorCode != 0 ? getSystemErrorMessage(errorCode) : null);
        this.addMessageIf(errorCode != 0 ? ("Error code: " ~ errorCodeToString(errorCode)) : null);
        return ResultCode.error;
    }

    int setUnsupportedError(uint errorCode, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        this.errorCode = errorCode;
        this.errorMessage = "Unsupported " ~ funcName ~ postfixMessage;
        this.funcName = funcName;
        this.file = file;
        this.line = line;
        return ResultCode.unsupported;
    }

    pragma(inline, true)
    void throwIf(E : Exception = Exception)()
    {
        if (isError)
            throwIt!E();
    }

    noreturn throwIt(E : Exception = Exception)(Throwable next = null)
    {
        static if (__traits(compiles, new E(errorCode, errorMessage, next, funcName, file, line)))
            throw new E(errorCode, errorMessage, next, funcName, file, line);
        else
            throw new E(errorMessage, file, line, next);
    }

    string toString() const pure
    {
        scope (failure) assert(0, "Assume nothrow failed");

        string result;

        if (errorMessage.length != 0)
            addLine(result, "Error message: " ~ errorMessage);
        if (errorCode != 0)
            addLine(result, "Error code: " ~ errorCodeToString(errorCode));
        if (file.length != 0)
            addLine(result, "File: " ~ file ~ " at line# " ~ line.to!string());
        if (funcName.length != 0)
            addLine(result, "Function: " ~ funcName);

        return result;
    }

    /**
     * Returns true if this instant is an error status
     * If errorCode != 0 or errorMessage.length != 0
     */
    pragma(inline, true)
    @property bool isError() const @nogc nothrow pure scope
    {
        return errorCode != 0 || errorMessage.length != 0;
    }

    /**
     * Returns true if this instant is an OK status
     * If errorCode == 0 and errorMessage.length == 0
     */
    pragma(inline, true)
    @property bool isOK() const @nogc nothrow pure scope
    {
        return errorCode == 0 && errorMessage.length == 0;
    }

public:
    string errorMessage;
    string file;
    string funcName;
    uint errorCode;
    uint line;
}

struct TryLimit
{
@nogc nothrow @safe:

    static assert(ptrdiff_t.sizeof >= 4); // Must be atleast 4 bytes

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(ptrdiff_t maxCount) pure
    {
        this.maxCount = maxCount;
        this._count = 0;
    }

    bool incOverLimit() pure
    {
        _count++;
        return isOverLimit;
    }

    void reset() pure
    {
        _count = 0;
    }

    @property ptrdiff_t count() const pure
    {
        return _count;
    }

    pragma(inline, true)
    @property bool isOverLimit() const pure
    {
        return _count > maxCount && maxCount >= 0;
    }

    @property bool isUnlimit() const pure
    {
        return maxCount < 0;
    }

public:
    enum defaultLimit = 3;
    const(ptrdiff_t) maxCount = defaultLimit;

private:
    ptrdiff_t _count;
}


private:

nothrow @safe unittest // cmp floating
{
    assert(cmp(2.0, 1.0) > 0);
    assert(cmp(2.0, 2.0) == 0);
    assert(cmp(0.0, 0.0) == 0);
    assert(cmp(1.0, 2.0) < 0);

    assert(isNaN(cmp(2.0, float.nan)));
    assert(isNaN(cmp(float.nan, 2.0)));
    assert(isNaN(cmp(float.nan, float.nan)));
    assert(isNaN(cmp(float.infinity, float.nan)));
    assert(isNaN(cmp(float.nan, -float.infinity)));

    assert(isNaN(cmp(-float.infinity, -float.infinity)));
    assert(isNaN(cmp(float.infinity, float.infinity)));
    assert(cmp(-float.infinity, float.infinity) < 0);
    assert(cmp(float.infinity, -float.infinity) > 0);
    assert(cmp(float.infinity, float.max) > 0);
    assert(cmp(-float.infinity, -float.max) < 0);
}

nothrow @safe unittest // cmp integral
{
    assert(cmp(2, 1) > 0);
    assert(cmp(2, 2) == 0);
    assert(cmp(0, 0) == 0);
    assert(cmp(1, 2) < 0);

    assert(cmp(int.min, int.max) < 0);
    assert(cmp(int.max, int.max) == 0);
    assert(cmp(int.min, int.min) == 0);
}

nothrow @safe unittest // sameSign
{
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

nothrow @safe unittest // CmpResult floating
{
    //import std.math : isNaN;

    assert(CmpResult(0.0, 0.0).isOp!"=="(0));
    assert(CmpResult(0.0, 0.0).isOp!"<="(0));
    assert(CmpResult(0.0, 0.0).isOp!">="(0));

    assert(CmpResult(1.0, 1.0).isOp!"=="(0));
    assert(CmpResult(1.0, 1.0).isOp!"<="(0));
    assert(CmpResult(1.0, 1.0).isOp!">="(0));

    assert(CmpResult(-double.max, -double.max).isOp!"=="(0));
    assert(CmpResult(-double.max, -double.max).isOp!"<="(0));
    assert(CmpResult(-double.max, -double.max).isOp!">="(0));

    assert(CmpResult(double.max, double.max).isOp!"=="(0));
    assert(CmpResult(double.max, double.max).isOp!"<="(0));
    assert(CmpResult(double.max, double.max).isOp!">="(0));

    assert(CmpResult(1.0, 2.0).isOp!"<"(0));
    assert(CmpResult(1.0, 2.0).isOp!"!="(0));
    assert(CmpResult(2.0, 1.0).isOp!">"(0));
    assert(CmpResult(2.0, 1.0).isOp!"!="(0));

    assert(CmpResult(-double.max, double.max).isOp!"<"(0));
    assert(CmpResult(-double.max, double.max).isOp!"!="(0));

    assert(CmpResult(double.max, -double.max).isOp!">"(0));
    assert(CmpResult(double.max, -double.max).isOp!"!="(0));

    assert(!CmpResult(double.nan, 2.0).isValid());
    assert(!CmpResult(1.0, double.nan).isValid());
    assert(!CmpResult(double.nan, double.nan).isValid());

    assert(!CmpResult(float.infinity, float.infinity).isValid());
    assert(!CmpResult(-double.infinity, -double.infinity).isValid());

    assert(CmpResult(-double.infinity, double.infinity).isOp!"<"(0));
    assert(CmpResult(-double.infinity, double.infinity).isOp!"<="(0));
    assert(CmpResult(-double.infinity, double.infinity).isOp!"!="(0));

    assert(CmpResult(double.infinity, -double.infinity).isOp!">"(0));
    assert(CmpResult(double.infinity, -double.infinity).isOp!">="(0));
    assert(CmpResult(double.infinity, -double.infinity).isOp!"!="(0));
}

nothrow @safe unittest // CmpResult integral
{
    assert(CmpResult(0, 0).isOp!"=="(0));
    assert(CmpResult(1, 2).isOp!"<"(0));
    assert(CmpResult(1, 2).isOp!"<="(0));
    assert(CmpResult(1, 2).isOp!"!="(0));
    assert(CmpResult(1, 1).isOp!"=="(0));
    assert(CmpResult(2, 1).isOp!">"(0));
    assert(CmpResult(2, 1).isOp!">="(0));
    assert(CmpResult(2, 1).isOp!"!="(0));
    assert(CmpResult(int.min, int.min).isOp!"=="(0));
    assert(CmpResult(int.max, int.max).isOp!"=="(0));
    assert(CmpResult(int.min, int.max).isOp!"<"(0));
    assert(CmpResult(int.min, int.max).isOp!"<="(0));
    assert(CmpResult(int.min, int.max).isOp!"!="(0));
    assert(CmpResult(int.max, int.min).isOp!">"(0));
    assert(CmpResult(int.max, int.min).isOp!">="(0));
    assert(CmpResult(int.max, int.min).isOp!"!="(0));
}

unittest // ResultIf
{
    auto e = ResultIf!int.error(1, "Error");
    assert(!e.isOK);
    assert(e.isError);
    assert(!e);
    assert(e.errorCode == 1);
    assert(e.errorMessage == "Error");

    auto r = ResultIf!int.ok(1);
    assert(!r.isError);
    assert(r.isOK);
    assert(r);
    assert(r.errorCode == 0);
    assert(r.errorMessage is null);
    assert(r == 1);
}

unittest // ResultStatus
{
    auto e = ResultStatus.error(1, "Error");
    assert(!e.isOK);
    assert(e.isError);
    assert(!e);
    assert(e.errorCode == 1);
    assert(e.errorMessage == "Error");

    auto r = ResultStatus.ok();
    assert(!r.isError);
    assert(r.isOK);
    assert(r);
    assert(r.errorCode == 0);
    assert(r.errorMessage is null);
}

unittest // TryLimit
{
    TryLimit defLimit;
    assert(!defLimit.isOverLimit);
    assert(!defLimit.isUnlimit);
    foreach (i; 0..TryLimit.defaultLimit)
    {
        assert(!defLimit.incOverLimit());
        assert(!defLimit.isOverLimit);
        assert(defLimit.count == i + 1);
    }
    assert(defLimit.incOverLimit());
    assert(defLimit.isOverLimit);
    assert(defLimit.count == TryLimit.defaultLimit + 1);

    TryLimit limit0 = TryLimit(0);
    assert(!limit0.isOverLimit);
    assert(!limit0.isUnlimit);
    assert(limit0.incOverLimit());
    assert(limit0.isOverLimit);
    assert(limit0.count == 1);

    TryLimit limit2 = TryLimit(2);
    assert(!limit2.isOverLimit);
    assert(!limit2.isUnlimit);
    foreach (i; 0..2)
    {
        assert(!limit2.incOverLimit());
        assert(!limit2.isOverLimit);
        assert(limit2.count == i + 1);
    }
    assert(limit2.incOverLimit());
    assert(limit2.isOverLimit);
    assert(limit2.count == 3);
    limit2.reset();
    assert(limit2.count == 0);
    assert(!limit2.isOverLimit);
    assert(!limit2.isUnlimit);
    foreach (i; 0..2)
    {
        assert(!limit2.incOverLimit());
        assert(!limit2.isOverLimit);
        assert(limit2.count == i + 1);
    }
    assert(limit2.incOverLimit());
    assert(limit2.isOverLimit);
    assert(limit2.count == 3);

    TryLimit unlimit = TryLimit(-1);
    assert(!unlimit.isOverLimit);
    assert(unlimit.isUnlimit);
    foreach (i; 0..100)
    {
        assert(!unlimit.incOverLimit());
        assert(!unlimit.isOverLimit);
        assert(unlimit.count == i + 1);
    }
    assert(!unlimit.isOverLimit);
}
