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

import std.traits : isIntegral;


string addLine(ref string lines, string line) nothrow pure @safe
{
    import std.ascii : newline;
    
    if (lines.length == 0)
        lines = line;
    else
        lines = lines ~ newline ~ line;
    return lines;
}

string errorCodeToString(I)(I errorCode) nothrow pure @safe
if (isIntegral!I)
{
    import std.conv : to;

    return "0x" ~ to!string(errorCode, 16) ~ " (" ~ to!string(errorCode) ~ ")";
}

/**
 * Simple aggregate to indicate if function result is an error or intended value
 */
struct ResultIf(T)
{
public:
    this(T value, int errorCode, string errorMessage = null)
    {
        this.value = value;
        this.errorCode = errorCode;
        this.errorMessage = errorMessage;
    }

    bool opCast(C: bool)() const @nogc nothrow pure @safe
    {
        return isOK;
    }

    string getErrorString() const nothrow pure @safe
    {
        string result = errorMessage;
        if (errorCode != 0)
            addLine(result, "Error code: " ~ errorCodeToString(errorCode));
        return result;
    }
    
    /**
     * Create this result-type as error
     */
    pragma(inline, true)
    static typeof(this) error(int errorCode, string errorMessage = null)
    in
    {
        assert(errorCode != 0 || errorMessage.length != 0);
    }
    do
    {
        return typeof(this)(T.init, errorCode, errorMessage);
    }

    /**
     * Create this result-type without error
     */
    pragma(inline, true)
    static typeof(this) ok(T value)
    {
        return typeof(this)(value, 0, null);
    }

    /**
     * Returns true if there is error-code or error-message
     */
    pragma(inline, true)
    @property bool isError() const @nogc nothrow pure @safe
    {
        return !isOK;
    }

    /**
     * Returns true if there is no error-code and error-message
     */
    pragma(inline, true)
    @property bool isOK() const @nogc nothrow pure @safe
    {
        return errorCode == 0 && errorMessage.length == 0;
    }
    
public:
    T value;
    alias value this;
    string errorMessage; // if lengh != 0, it considers an error
    int errorCode = -1;  // -1 = Uninitialized is explicitely an error
}

struct ResultStatus
{
nothrow @safe:

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

    pragma(inline, true)
    static typeof(this) error(int errorCode, string errorMessage, string errorFormat = null) @nogc pure
    {
        return ResultStatus(true, errorCode, errorMessage, errorFormat);
    }

    pragma(inline, true)
    static typeof(this) ok() @nogc pure
    {
        return ResultStatus(false, 0, null);
    }

    string toString() const pure
    {
        import std.conv : to;

        scope (failure) assert(0);

        return isOK
            ? "Status: " ~ to!string(errorStatus)
            : "Status: " ~ to!string(errorStatus)
                ~ "\nCode: " ~ errorCodeToString(errorCode)
                ~ "\nMessage: " ~ errorMessage;
    }

    pragma(inline, true)
    @property bool isError() const @nogc pure
    {
        return !isOK;
    }

    pragma(inline, true)
    @property bool isOK() const @nogc pure
    {
        return !errorStatus;
    }

public:
    string errorFormat;
    string errorMessage;
    int errorCode;
    bool errorStatus;
}


private:

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
