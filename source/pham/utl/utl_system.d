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

import std.traits : isIntegral;

import pham.utl.utl_disposable : DisposingReason;
import pham.utl.utl_result : osCharToString, osWCharToString;
public import pham.utl.utl_result : ResultCode, ResultStatus, errorCodeToString;

/**
 * Represents a wrapper struct for operating system handles
 */
struct SafeHandle(Handle, alias doClose, Handle invalidHandle = Handle.init)
if (isIntegral!Handle || is(Handle == void*))
{
    import std.traits : ReturnType;
    
nothrow @safe:

public:
    this(Handle handle) @nogc
    {
        this._handle = handle;
    }

    // Copy constructor
    //this(ref return scope SafeHandle rhs) {}
    @disable this(ref SafeHandle);

    // Move constructor
    this(return scope SafeHandle rhs)
    {
        // Check to avoid move into it self
        if (!sameHandle(this._handle, rhs._handle))
        {
            doDispose(DisposingReason.other);
            this._handle = rhs._handle;
            rhs._handle = invalidHandle;
        }
    }
    //@disable this(SafeHandle);

    ~this()
    {
        doDispose(DisposingReason.destructor);
    }

    void opAssign(Handle rhs)
    {
        if (!sameHandle(this._handle, rhs))
        {
            doDispose(DisposingReason.other);
            this._handle = rhs;
        }
    }

    bool opCast(C: bool)() const @nogc pure
    {
        return isValid;
    }

    /**
     * Freeing/Releases resources
     */
    int close()
    {
        return doDispose(DisposingReason.other);
    }
    
    /**
     * Freeing/Releases resources
     */
    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose)
    {
        return doDispose(disposingReason);
    }

    pragma(inline, true)
    @property inout(Handle) handle() inout @nogc pure
    {
        return _handle;
    }

    /**
     * Gets a value indicating whether the handle value is valid
     */
    pragma(inline, true)
    @property bool isValid() const @nogc pure
    {
        return !sameHandle(_handle, invalidHandle);
    }

    // Do not declare alias as disabling copy constructor
    //alias this = handle;

private:
    int doDispose(const(DisposingReason) disposingReason) @trusted
    {
        int result = ResultCode.ok;
        if (!sameHandle(_handle, invalidHandle))
        {
            static if (is(ReturnType!doClose : int))
                result = doClose(_handle);
            else
                doClose();
            _handle = invalidHandle;
        }
        return result;
    }

    pragma(inline, true)
    static bool sameHandle(const(Handle) lhs, const(Handle) rhs) @nogc nothrow pure @safe
    {
        static if (is(Handle == void*))
            return cast(size_t)lhs == cast(size_t)rhs;
        else
            return lhs == rhs;
    }
    
private:
    Handle _handle = invalidHandle;
}

/**
 * Returns current computer-name of running process
 */
string currentComputerName() nothrow @trusted
{
    version(Windows)
    {
        import core.sys.windows.winbase : GetComputerNameW;

        wchar[1_000] result = '\0';
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
        pragma(msg, __FUNCTION__ ~ "() not supported");
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

        wchar[1_000] result = '\0';
        const readLen = GetModuleFileNameW(null, &result[0], result.length - 1);
        return readLen != 0 ? osWCharToString(result[0..readLen]) : null;
    }
    else version(Posix)
    {
        import core.sys.posix.unistd : readlink;

        char[1_000] result = '\0';
        const readLen = readlink("/proc/self/exe".ptr, &result[0], result.length - 1);
        return readLen != -1 ? osCharToString(result[0..readLen]) : null;
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
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

        wchar[1_000] result = '\0';
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
        pragma(msg, __FUNCTION__ ~ "() not supported");
        return null;
    }
}

void sleep(uint milliseconds) nothrow @trusted
{
    version(Windows)
    {
        import core.sys.windows.winbase : winSleep = Sleep;

        winSleep(milliseconds);
    }
    else version(Posix)
    {
        import core.stdc.errno : EINTR, errno;
        import core.sys.posix.time : nanosleep, timespec;

        timespec tin;
        tin.tv_sec = milliseconds / 1_000;
        tin.tv_nsec = (milliseconds % 1_000) * 1_000_000;

        do
        {
            timespec tout;
            if (!nanosleep(&tin, &tout))
                return;
            tin = tout;
        }
        while (errno == EINTR && tin != timespec.init);
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
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

version(Windows)
nothrow @safe unittest // SafeHandle
{
    import core.sys.windows.winbase;
    import core.sys.windows.windef;
    //import std.string : toStringz;

    alias LibHandle = SafeHandle!(HMODULE, FreeLibrary, null);

    // Constructor
    auto dllHandle = LibHandle(() @trusted { return LoadLibraryA("Kernel32.dll"); }());
    assert(dllHandle.isValid);
    assert(dllHandle);
    dllHandle.dispose();
    assert(!dllHandle.isValid);
    assert(!dllHandle);

    // Assign
    dllHandle = LibHandle(() @trusted { return LoadLibraryA("Kernel32.dll"); }());
    assert(dllHandle.isValid);
    assert(dllHandle);
    dllHandle.dispose();
    assert(!dllHandle.isValid);
    assert(!dllHandle);
}
