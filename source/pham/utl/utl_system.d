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

module pham.utl.utl_system;

import pham.utl.utl_result : osCharToString, osWCharToString;
public import pham.utl.utl_result : errorCodeToString, ResultStatus;


/**
 * Returns current computer-name of running process
 */
string currentComputerName() nothrow @trusted
{
    version(Windows)
    {
        import core.sys.windows.winbase : GetComputerNameW;

        wchar[1_000] result = void;
        uint len = result.length - 1;
        if (GetComputerNameW(&result[0], &len))
            return osWCharToString(result[0..len]);
        else
            return null;
    }
    else version(Posix)
    {
        import core.sys.posix.unistd : gethostname;

        char[1_000] result = '\0';
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
    version(Windows)
    {
        import core.sys.windows.winbase : GetModuleFileNameW;

        wchar[1_000] result = void;
        const readLen = GetModuleFileNameW(null, &result[0], result.length - 1);
        return readLen != 0 ? osWCharToString(result[0..readLen]) : null;
    }
    else version(Posix)
    {
        import core.sys.posix.unistd : readlink;

        char[1_000] result = void;
        const readLen = readlink("/proc/self/exe".ptr, &result[0], result.length - 1);
        return readLen != -1 ? osCharToString(result[0..readLen]) : null;
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
    version(Windows)
    {
        import core.sys.windows.winbase : GetUserNameW;

        wchar[1_000] result = void;
        uint len = result.length - 1;
        if (GetUserNameW(&result[0], &len))
            return osWCharToString(result[0..len]);
        else
            return null;
    }
    else version(Posix)
    {
        import core.sys.posix.unistd : getlogin_r;

        char[1_000] result = '\0';
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


private:

nothrow @safe unittest // currentComputerName
{
    assert(currentComputerName().length != 0);
}

nothrow @safe unittest // currentProcessId
{
    assert(currentProcessId() != 0);
}

version(Windows) // Posix - Not work for if not attached to terminal
nothrow @safe unittest // currentUserName
{
    assert(currentUserName().length != 0);
}
