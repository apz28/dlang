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

module pham.utl.result;

import std.math.traits : isNaN;
import std.traits : isFloatingPoint, isIntegral, isScalarType;

@safe:

string addLine(ref string lines, string line) nothrow pure
{
    import std.ascii : newline;

    if (lines.length == 0)
        lines = line;
    else
        lines = lines ~ newline ~ line;
    return lines;
}

bool addLineIf(ref string lines, string line) nothrow pure
{
    if (line.length)
    {
        addLine(lines, line);
        return true;
    }
    else
        return false;
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
pragma(inline, true)
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

        version (BigEndian)
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

// This function is called by the compiler when dealing with array
// comparisons in the semantic analysis phase of CmpExp. The ordering
// comparison is lowered to a call to this template.
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
    import std.conv : to;

    return "0x" ~ to!string(errorCode, 16) ~ " (" ~ to!string(errorCode) ~ ")";
}

string getSystemErrorMessage(const(int) errorNo) nothrow @trusted
in
{
    assert(errorNo != 0);
}
do
{
    version (Windows)
    {
        import core.sys.windows.winbase : FormatMessageA, FORMAT_MESSAGE_FROM_SYSTEM, FORMAT_MESSAGE_IGNORE_INSERTS;

        char[1_000] buf = void;
        auto n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, errorNo, 0, buf.ptr, buf.length, null);
        while (n > 0 && buf[n-1] < ' ')
            n--;
        return n > 0 ? buf[0..n].idup : null;
    }
    else version (Posix)
    {
        import core.stdc.string : strlen, strerror_r;

        char[1_000] buf;
        const(char)* p;

        version (CRuntime_Glibc)
            p = strerror_r(errorNo, buf.ptr, buf.length);
        else if (!strerror_r(errorNo, buf.ptr, buf.length))
            p = buf.ptr;
        if (p !is null)
        {
            auto n = p.strlen;
            while (n > 0 && p[n-1] < ' ')
                n--;
        }
        return p !is null ? p[0..p.strlen].idup : null;
    }
    else
        static assert(0, "Unsupport target");
}

pragma(inline, true)
uint lastSystemError() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetLastError;

        return GetLastError();
    }
    else version (Posix)
    {
        import core.stdc.errno : errno;

        return errno;
    }
    else
        static assert(0, "Unsupport target");
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
int sameSign(LHS, RHS)(const(LHS) lhs, const(RHS) rhs) @nogc nothrow pure @safe
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

    alias state this;

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
    this(T value, ResultStatus status)
    {
        this.value = value;
        this.status = status;
    }

    bool opCast(C: bool)() const @nogc nothrow pure
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
    static typeof(this) error(int errorCode, string errorMessage, string errorFormat = null)
    {
        return typeof(this)(T.init, ResultStatus.error(errorCode, errorMessage, errorFormat));
    }

    pragma(inline, true)
    static typeof(this) error(T value, int errorCode, string errorMessage, string errorFormat = null)
    {
        return typeof(this)(value, ResultStatus.error(errorCode, errorMessage, errorFormat));
    }

    /**
     * Create this result-type without error
     */
    pragma(inline, true)
    static typeof(this) ok(T value)
    {
        return typeof(this)(value, ResultStatus.ok());
    }

    @property int errorCode() const @nogc nothrow pure
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
    @property bool isError() const @nogc nothrow pure
    {
        return status.isError;
    }

    /**
     * Returns true if there is no error-code and error-message
     */
    pragma(inline, true)
    @property bool isOK() const @nogc nothrow pure
    {
        return status.isOK;
    }

public:
    T value;
    alias value this;
    ResultStatus status = ResultStatus.defaultError();
}

struct ResultStatus
{
nothrow @safe:

    enum defaultErrorCode = int.min;

public:
    this(bool errorStatus, int errorCode, string errorMessage, string errorFormat = null) @nogc pure
    {
        this.errorStatus = errorStatus;
        this.errorCode = errorCode;
        this.errorMessage = errorMessage;
        this.errorFormat = errorFormat;
    }

    bool opCast(C: bool)() const @nogc pure
    {
        return isOK;
    }

    bool clone(ResultStatus source) @nogc pure
    {
        this.errorFormat = source.errorFormat;
        this.errorMessage = source.errorMessage;
        this.errorCode = source.errorCode;
        this.errorStatus = source.errorStatus;
        return this.errorStatus;
    }

    static typeof(this) defaultError() @nogc pure
    {
        return typeof(this)(true, defaultErrorCode, null, null);
    }

    pragma(inline, true)
    static typeof(this) error(int errorCode, string errorMessage, string errorFormat = null) @nogc pure
    {
        return typeof(this)(true, errorCode, errorMessage, errorFormat);
    }

    string getErrorString() const pure
    {
        string result = errorMessage;
        if (errorCode != 0)
            addLine(result, "Error code: " ~ errorCodeToString(errorCode));
        return result;
    }

    pragma(inline, true)
    static typeof(this) ok() @nogc pure
    {
        return typeof(this)(false, 0, null, null);
    }

    string toString() const pure
    {
        import std.conv : to;
        scope (failure) assert(0, "Assume nothrow failed");

        string result = "Error status: " ~ to!string(errorStatus);
        if (isError)
        {
            if (errorMessage.length != 0)
                addLine(result, "Error message: " ~ errorMessage);
            if (errorCode != 0)
                addLine(result, "Error code: " ~ errorCodeToString(errorCode));
        }
        return result;
    }

    pragma(inline, true)
    @property bool isError() const @nogc pure
    {
        return errorStatus;
    }

    pragma(inline, true)
    @property bool isOK() const @nogc pure
    {
        return !isError;
    }

public:
    string errorFormat;
    string errorMessage;
    int errorCode;
    bool errorStatus;
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
