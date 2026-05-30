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

import core.time : Duration;
import std.process : Pid;
import std.traits : isIntegral;

import pham.utl.utl_disposable : DisposingReason;
import pham.utl.utl_result : lastSystemError, osCharToString, osWCharToString;
public import pham.utl.utl_result : ResultCode, ResultIf, ResultStatus,
    errorCodeToString;

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
    version(Posix)
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
    else version(Windows)
    {
        import core.sys.windows.winbase : GetComputerNameW;

        wchar[1_000] result = '\0';
        uint len = result.length - 1;
        if (GetComputerNameW(&result[0], &len))
            return osWCharToString(result[0..len]);
        else
            return null;
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
        assert(0, __FUNCTION__ ~ "() not supported");
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
    version(Posix)
    {
        import core.sys.posix.unistd : readlink;

        char[1_000] result = '\0';
        const readLen = readlink("/proc/self/exe".ptr, &result[0], result.length - 1);
        return readLen != -1 ? osCharToString(result[0..readLen]) : null;
    }
    else version(Windows)
    {
        import core.sys.windows.winbase : GetModuleFileNameW;

        wchar[1_000] result = '\0';
        const readLen = GetModuleFileNameW(null, &result[0], result.length - 1);
        return readLen != 0 ? osWCharToString(result[0..readLen]) : null;
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
        assert(0, __FUNCTION__ ~ "() not supported");
    }
}

/**
 * Returns current os-account-name of running process
 */
string currentUserName() nothrow @trusted
{
    version(Posix)
    {
        import core.sys.posix.unistd : getlogin_r;

        char[1_000] result = '\0';
        uint len = result.length - 1;
        if (getlogin_r(&result[0], len) == 0)
            return osCharToString(result[]);
        else
            return null;
    }
    else version(Windows)
    {
        import core.sys.windows.winbase : GetUserNameW;

        wchar[1_000] result = '\0';
        uint len = result.length - 1;
        if (GetUserNameW(&result[0], &len))
            return osWCharToString(result[0..len]);
        else
            return null;
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
        assert(0, __FUNCTION__ ~ "() not supported");
    }
}

ResultIf!Pid runDefaultBrowser(string url) nothrow @trusted
{
    import std.process : Config, spawnProcess;

    version(linux)
    {
        // On Linux, 'xdg-open' or 'sensible-browser' are standard tools
        string[] arguments = ["xdg-open", url];
    }
    else version(OSX)
    {
        // On macOS, 'open' command handles URLs
        string[] arguments = ["open", url];
    }
    else version(Posix)
    {
        // Fallback for other POSIX systems or show an error
        string[] arguments = ["sensible-browser", url];
    }
    else version(Windows)
    {
        // On Windows, 'cmd /c start' is a reliable way to open a URL
        string[] arguments = ["cmd", "/c", "start", url];
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
        assert(0, __FUNCTION__ ~ "() not supported");
    }

    try
    {
        auto pid = spawnProcess(arguments, null, Config.detached);
        return ResultIf!Pid.ok(pid);
    }
    catch (Exception e)
    {
        return ResultIf!Pid.error(-1, e.msg);
    }
}

void sleep(scope const(Duration) duration) nothrow @safe
{
    const totalMilliSeconds = duration.total!"msecs"();
    return totalMilliSeconds > uint.max
        ? sleep(uint.max)
        : sleep(cast(uint)totalMilliSeconds);
}

void sleep(uint milliSeconds) nothrow @trusted
{
    version(Posix)
    {
        import core.stdc.errno : EINTR, errno;
        import core.sys.posix.time : nanosleep, timespec;

        timespec tin;
        tin.tv_sec = milliSeconds / 1_000;
        tin.tv_nsec = (milliSeconds % 1_000) * 1_000_000;

        do
        {
            timespec tout;
            if (!nanosleep(&tin, &tout))
                return;
            tin = tout;
        }
        while (errno == EINTR && tin != timespec.init);
    }
    else version(Windows)
    {
        import core.sys.windows.winbase : winSleep = Sleep;

        winSleep(milliSeconds);
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
        assert(0, __FUNCTION__ ~ "() not supported");
    }
}

alias WaitForCallbackEvent = int delegate(void* context, long elapsedMilliSeconds) nothrow;

ResultIf!uint waitFor(Pid pid, Duration timeOut, WaitForCallbackEvent queryCallback, void* queryContext,
    const(ushort) milliSecondIntervals = 200) nothrow @trusted
in
{
    assert(milliSecondIntervals > 0 && milliSecondIntervals <= 60_000);
}
do
{
    const totalMilliSeconds = timeOut.total!"msecs"();
    long elapsedMilliSeconds;

    version(Posix)
    {
        import core.sys.posix.sys.wait : WIFEXITED, WTERMSIG, WIFSIGNALED, WEXITSTATUS, waitpid;
        import core.stdc.errno : ECHILD, EINTR, errno;

        while (true)
        {
            elapsedMilliSeconds += milliSecondIntervals;
            int status;
            const wr = waitpid(pid.osHandle, &status, 0);

            if (wr == -1)
            {
                if (errno == ECHILD)
                    return ResultIf!uint.ok(errno);

                if (errno == EINTR)
                {
                    elapsedMilliSeconds -= milliSecondIntervals;
                    continue;
                }
            }

            if (WIFEXITED(status))
            {
                const exitCode = WEXITSTATUS(status);
                return ResultIf!uint.ok(exitCode);
            }

            if (WIFSIGNALED(status))
            {
                const exitCode = WTERMSIG(status);
                return ResultIf!uint.ok(exitCode);
            }

            if (totalMilliSeconds > 0 && elapsedMilliSeconds >= totalMilliSeconds)
                return ResultIf!uint.error(ResultCode.timeOut, "TimeOut");

            if (queryCallback !is null)
            {
                const qr = queryCallback(queryContext, elapsedMilliSeconds);
                if (qr != 0)
                    return ResultIf!uint.error(ResultCode.canceled, "Canceled");
            }
        }
    }
    else version(Windows)
    {
        import core.sys.windows.winbase : STILL_ACTIVE, WAIT_ABANDONED, WAIT_FAILED,
            GetExitCodeProcess, WaitForSingleObject;
        import core.sys.windows.windef : DWORD;
        import core.sys.windows.winerror : WAIT_TIMEOUT;

        while (true)
        {
            elapsedMilliSeconds += milliSecondIntervals;
            const wr = WaitForSingleObject(pid.osHandle, milliSecondIntervals);

            if (wr == WAIT_ABANDONED)
                return ResultIf!uint.ok(wr);

            if (wr != WAIT_TIMEOUT)
            {
                DWORD osExitCode;
                if (GetExitCodeProcess(pid.osHandle, &osExitCode))
                {
                    if (osExitCode != STILL_ACTIVE)
                        return ResultIf!uint.ok(osExitCode);
                }
                else if (wr == WAIT_FAILED)
                    return ResultIf!uint.error(lastSystemError(), "Failed");
            }

            if (totalMilliSeconds > 0 && elapsedMilliSeconds >= totalMilliSeconds)
                return ResultIf!uint.error(ResultCode.timeOut, "TimeOut");

            if (queryCallback !is null)
            {
                const qr = queryCallback(queryContext, elapsedMilliSeconds);
                if (qr != 0)
                    return ResultIf!uint.error(ResultCode.canceled, "Canceled");
            }
        }
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
        assert(0, __FUNCTION__ ~ "() not supported");
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
