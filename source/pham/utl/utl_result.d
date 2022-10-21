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

struct ResultIf(T)
{
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

    pragma(inline, true)
    static typeof(this) ok(T value)
    {
        return typeof(this)(value, 0, null);
    }

    pragma(inline, true)
    @property bool isError() const @nogc nothrow pure @safe
    {
        return !isOK;
    }

    pragma(inline, true)
    @property bool isOK() const @nogc nothrow pure @safe
    {
        return errorCode == 0 && errorMessage.length == 0;
    }

    alias value this;

public:
    T value;
    string errorMessage;
    int errorCode;
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
                ~ "\nCode: " ~ to!string(errorCode)
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
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.result.ResultIf");

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
    import pham.utl.test;
    traceUnitTest!("pham.utl")("unittest pham.utl.result.ResultStatus");

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
