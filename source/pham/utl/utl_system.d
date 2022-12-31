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

import std.traits : isIntegral;

public import pham.utl.result : errorCodeToString, ResultStatus;


/**
 * Returns current computer-name of running process
 */
string currentComputerName() nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winbase : GetComputerNameW;

        wchar[1000] result = void;
        uint len = result.length - 1;
        if (GetComputerNameW(&result[0], &len))
            return osWCharToString(result[0..len]);
        else
            return null;
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : gethostname;

        char[1000] result = '\0';
        uint len = result.length - 1;
        if (gethostname(&result[0], len) == 0)
        {
            return osCharToString(result[]);
        }
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

        wchar[1000] result = void;
        const len = GetModuleFileNameW(null, &result[0], result.length - 1);
        return osWCharToString(result[0..len]);
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : readlink;

        char[1000] result = '\0';
        uint len = result.length - 1;
        len = readlink("/proc/self/exe".ptr, &result[0], len);
        return osCharToString(result[]);
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

        wchar[1000] result = void;
        uint len = result.length - 1;
        if (GetUserNameW(&result[0], &len))
            return osWCharToString(result[0..len]);
        else
            return null;
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : getlogin_r;

        char[1000] result = '\0';
        uint len = result.length - 1;
        if (getlogin_r(&result[0], len) == 0)
            return osCharToString(result[]);
        else
            return null;
    }
    else
    {
        pragma(msg, "currentUserName() not supported");
        return "";
    }
}

string genericErrorMessage(I)(string apiName, I errorCode) nothrow @safe
if (isIntegral!I)
{
    return apiName ~ " - error code: " ~ errorCodeToString(errorCode);
}

ResultStatus lastSocketError(string apiName) nothrow @safe
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

    string windowErrorString(DWORD errorCode,
        int langId = LANG_NEUTRAL, int subLangId = SUBLANG_DEFAULT) nothrow @trusted
    {
        try 
        {
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
                return osWCharToString(buf[0..len]);
            else
                return null;
        } catch (Exception) return null;
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

        const len = strlen(bufPtr);
        return osCharToString(bufPtr[0..len]);
    }
}


private:

string osCharToString(scope const(char)[] v) nothrow @safe
{
    import std.conv : to;

    scope (failure) assert(0);
    
    auto result = to!string(v);
    while (result.length && result[$ - 1] <= ' ')
        result = result[0..$ - 1];
    return result;
}

string osWCharToString(scope const(wchar)[] v) nothrow @safe
{
    import std.conv : to;

    scope (failure) assert(0);
    
    auto result = to!string(v);
    while (result.length && result[$ - 1] <= ' ')
        result = result[0..$ - 1];
    return result;
}

nothrow @safe unittest // currentComputerName
{
    assert(currentComputerName().length != 0);
}

nothrow @safe unittest // currentProcessId
{
    assert(currentProcessId() != 0);
}

nothrow @safe unittest // currentUserName
{
    assert(currentUserName().length != 0);
}
