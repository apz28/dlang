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

module pham.io.io_error;

import pham.utl.utl_array_dictionary;
import pham.utl.utl_result : addLine, errorCodeToString;

@safe:

class IOException : Exception
{
@safe:

public:
    this(uint errorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorMessage, file, line, next);
        this.errorCode = errorCode;
        this.funcName = funcName;
    }

    override string toString() nothrow @trusted
    {
        scope (failure) assert(0, "Assume nothrow failed");

        auto result = super.toString();
        if (errorCode != 0)
            addLine(result, "Error code: " ~ errorCodeToString(errorCode));

        auto e = next;
        while (e !is null)
        {
            addLine(result, "");
            addLine(result, e.toString());
            e = e.next;
        }

        return result;
    }

public:
    string funcName;
    uint errorCode;
}

class StreamException : IOException
{
@safe:

public:
    this(uint errorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorCode, errorMessage, next, funcName, file, line);
    }
}

class StreamReadException : StreamException
{
@safe:

public:
    this(uint errorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorCode, errorMessage, next, funcName, file, line);
    }
}

class StreamWriteException : StreamException
{
@safe:

public:
    this(uint errorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorCode, errorMessage, next, funcName, file, line);
    }
}

string getIOAPIName(scope const(char)[] mapFunctionName) nothrow pure
{
    if (auto e = mapFunctionName in mapIOAPINames)
        return *e;

    assert(0, "Invalid mapFunctionName: " ~ mapFunctionName);
}

static immutable Dictionary!(string, string) mapIOAPINames;


private:

import core.attribute : standalone;

@standalone
shared static this() nothrow @trusted
{
    version(Posix)
    {
        auto names = Dictionary!(string, string)(15, 10);

        names["openFile"] = "open";
        names["readFile"] = "read";
        names["removeFile"] = "remove";
        names["flushFile"] = "fsync";
        names["getLengthFile"] = "lseek64";
        names["closeFile"] = "close";
        names["createFilePipes"] = "pipe";
        names["seekFile"] = "lseek64";
        names["setLengthFile"] = "ftruncate64";
        names["writeFile"] = "write";

        mapIOAPINames = cast(immutable)names;
    }
    else version(Windows)
    {
        auto names = Dictionary!(string, string)(15, 10);

        names["openFile"] = "CreateFileW";
        names["readFile"] = "ReadFile";
        names["removeFile"] = "DeleteFileW";
        names["flushFile"] = "FlushFileBuffers";
        names["getLengthFile"] = "GetFileSizeEx";
        names["closeFile"] = "CloseHandle";
        names["createFilePipes"] = "CreatePipe";
        names["seekFile"] = "SetFilePointer";
        names["setLengthFile"] = "SetEndOfFile";
        names["writeFile"] = "WriteFile";
        //names[""] = "";

        mapIOAPINames = cast(immutable)names;
    }
    else
        pragma(msg, "Unsupported system for " ~ __MODULE__);
}
