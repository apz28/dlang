/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2023 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.io.error;

import pham.utl.result : errorCodeToString, getSystemErrorMessage;
import pham.io.type : IOResult;

@safe:

struct IOError
{
@safe:

public:
    this(uint errorNo, string message,
        string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        this.errorNo = errorNo;
        this.message = message;
        this.file = file;
        this.line = line;
    }

    bool opCast(C: bool)() const @nogc nothrow pure
    {
        return isOK;
    }

    bool addMessageIf(string msg) nothrow pure
    {
        if (msg.length)
        {
            this.message ~= "\n" ~ msg;
            return true;
        }
        else
            return false;
    }
    
    IOResult clone(IOError source, IOResult result) nothrow pure
    {
        this.file = source.file;
        this.message = source.message;
        this.errorNo = source.errorNo;
        this.line = source.line;
        return result;
    }
    
    static IOError failed(uint errorNo, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        IOError result;
        result.setFailed(errorNo, postfixMessage, funcName, file, line);
        return result;
    }

    pragma(inline, true)
    static typeof(this) ok() nothrow pure
    {
        return typeof(this)(0, null, null, 0);
    }
    
    pragma(inline, true)
    IOResult reset() nothrow
    {
        this.file = this.message = null;
        this.errorNo = this.line = 0;
        return IOResult.success;
    }

    IOResult set(uint errorNo, string message, IOResult result = IOResult.failed,
        string file = __FILE__, uint line = __LINE__) nothrow
    {
        this.errorNo = errorNo;
        this.message = message;
        this.file = file;
        this.line = line;
        return result;
    }

    IOResult setFailed(uint errorNo, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        this.errorNo = errorNo;
        this.message = "Failed " ~ funcName ~ postfixMessage;
        this.file = file;
        this.line = line;
        this.addMessageIf(errorNo != 0 ? getSystemErrorMessage(errorNo) : null);
        this.addMessageIf(errorNo != 0 ? ("Error code: " ~ errorCodeToString(errorNo)) : null);
        return IOResult.failed;
    }

    IOResult setUnsupported(uint errorNo, string postfixMessage = null,
        string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
    {
        this.errorNo = errorNo;
        this.message = "Unsupported " ~ funcName ~ postfixMessage;
        this.file = file;
        this.line = line;
        return IOResult.unsupported;
    }

    pragma(inline, true)
    void throwIf(E : StreamException = StreamException)()
    {
        if (errorNo != 0 || message.length != 0)
            throwIt!E();
    }

    void throwIt(E : StreamException = StreamException)()
    {
        throw new E(errorNo, message, file, line);
    }

    /**
     * Returns true if there is error-code or error-message
     */
    pragma(inline, true)
    @property bool isError() const @nogc nothrow pure
    {
        return errorNo != 0 || message.length != 0;
    }

    /**
     * Returns true if there is no error-code and error-message
     */
    pragma(inline, true)
    @property bool isOK() const @nogc nothrow pure
    {
        return errorNo == 0 && message.length == 0;
    }

public:
    string file;
    string message;
    uint errorNo;
    uint line;
}

class IOException : Exception
{
@safe:

public:
    this(uint errorNo, string message,
        string file = __FILE__, uint line = __LINE__, Throwable next = null) nothrow pure
    {
        super(message, file, line, next);
        this.errorNo = errorNo;
    }

    override string toString() nothrow @trusted
    {
        import std.format : format;
        scope (failure) assert(0, "Assume nothrow failed");

        auto result = super.toString();
        if (errorNo != 0)
            result ~= "\nError code: " ~ format!"0x%.8d [%d]"(errorNo, errorNo);

        auto e = next;
        while (e !is null)
        {
            result ~= "\n\n" ~ e.toString();
            e = e.next;
        }

        return result;
    }

public:
    const(uint) errorNo;
}

class StreamException : IOException
{
@safe:

public:
    this(uint errorNo, string message,
        string file = __FILE__, uint line = __LINE__, Throwable next = null) nothrow pure
    {
        super(errorNo, message, file, line, next);
    }
}

class StreamReadException : StreamException
{
@safe:

public:
    this(uint errorNo, string message,
        string file = __FILE__, uint line = __LINE__, Throwable next = null) nothrow pure
    {
        super(errorNo, message, file, line, next);
    }
}

class StreamWriteException : StreamException
{
@safe:

public:
    this(uint errorNo, string message,
        string file = __FILE__, uint line = __LINE__, Throwable next = null) nothrow pure
    {
        super(errorNo, message, file, line, next);
    }
}
