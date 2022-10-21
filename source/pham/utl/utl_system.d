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

module pham.utl.system;

public import pham.utl.result : ResultStatus;

string genericErrorMessage(string apiName, int errorCode) nothrow @trusted
{
import std.conv : to;

    return apiName ~ " error " ~ to!string(errorCode);
}

string genericErrorMessage(string apiName, uint errorCode) nothrow @trusted
{
import std.conv : to;

    return apiName ~ " error 0x" ~ to!string(errorCode, 16);
}

ResultStatus lastSocketError(string apiName) nothrow @trusted
{
    auto code = lastSocketErrorCode();
    auto message = systemErrorString(apiName, code);
    return ResultStatus.error(code, message);
}

int lastSocketErrorCode() @nogc nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winsock2 : WSAGetLastError;

        return WSAGetLastError();
    }
    else version (Posix)
    {
        import core.stdc.errno : errno;

        return errno;
    }
    else
    {
        pragma(msg, "No socket error code for this platform.");
        return 0;
    }
}

string systemErrorString(string apiName, int errorCode) nothrow @trusted
{
    version (Windows)
    {
        auto result = windowErrorString(errorCode);
        return result.length ? result : genericErrorMessage(apiName, errorCode);
    }
    else version (Posix)
    {
        auto result = posixErrorString(errorCode);
        return result.length ? result : genericErrorMessage(apiName, errorCode);
    }
    else
    {
        pragma(msg, "No system error message for this platform.");
        return genericErrorMessage(apiName, errorCode);
    }
}

version (Windows)
{
    import core.sys.windows.winbase : FormatMessageW, LocalFree,
        FORMAT_MESSAGE_ALLOCATE_BUFFER, FORMAT_MESSAGE_FROM_SYSTEM, FORMAT_MESSAGE_IGNORE_INSERTS;
    import core.sys.windows.windef : DWORD;
    import core.sys.windows.winnt : LANG_NEUTRAL, SUBLANG_DEFAULT, LPWSTR;
    import std.conv : to;

    string windowErrorString(DWORD errorCode,
        int langId = LANG_NEUTRAL, int subLangId = SUBLANG_DEFAULT) nothrow @trusted
    {
        scope (failure)
            return null;

        wchar* buf = null;
        auto len = FormatMessageW(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
            null,
            errorCode,
            langId,
            cast(LPWSTR)&buf,
            0,
            null);
        scope (exit)
        {
            if (buf)
                LocalFree(buf);
        }

        if (len)
        {
            while (len && (buf[len - 1] == ' ' || buf[len - 1] == '\n' || buf[len - 1] == '\r'))
                len--;
            return to!string(buf[0..len]);
        }
        else
            return null;
    }
}
else version (Posix)
{
    string posixErrorString(int errorCode) nothrow @trusted
    {
        char[1000] buf = '\0';
        const(char)* bufPtr;

        version (GNU_STRERROR)
        {
            bufPtr = strerror_r(errorCode, buf.ptr, buf.length);
        }
        else
        {
            auto errs = strerror_r(errorCode, buf.ptr, buf.length);
            if (errs == 0)
                bufPtr = buf.ptr;
            else
                return null;
        }

        auto len = strlen(bufPtr);
        while (len && (bufPtr[len - 1] == ' ' || bufPtr[len - 1] == '\n' || bufPtr[len - 1] == '\r'))
            len--;
        return bufPtr[0..len].idup;
    }
}
