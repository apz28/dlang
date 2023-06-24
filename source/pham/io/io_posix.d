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

module pham.io.posix;

version (Posix):

import core.sys.posix.fcntl;
import core.sys.posix.unistd : close, lseek64, pipe, read, ftruncate64, write;
import core.stdc.stdio : remove;

import pham.io.type : SeekOrigin, StreamOpenInfo, StreamResult;

alias Handle = int;
enum invalidHandleValue = -1;

string getSystemErrorMessage(const(int) errorNo) nothrow @trusted
in
{
    assert(errorNo != 0);
}
do
{
    import core.stdc.string : strlen, strerror_r;

    char[1_000] buf = void;
    const(char)* p;

    version (CRuntime_Glibc)
        p = strerror_r(errorNo, buf.ptr, buf.length);
    else if (!strerror_r(errorNo, buf.ptr, buf.length))
        p = buf.ptr;
    return p !is null ? p[0..p.strlen].idup : null;
}

pragma(inline, true)
int lastErrorNo() nothrow @safe
{
    return errno;
}

alias closeFile = close;

int createFilePipes(const(bool) asInput, out Handle inputHandle, out Handle outputHandle,
    uint bufferSize = 0) nothrow @trusted
{
    Handle[2] handles = invalidHandleValue;
    int result;
    do
    {
        result = pipe(handles);
    }
    while (result < 0 && errno == EINTR);
    inputHandle = handles[0];
    outputHandle = handles[1];
    return result;
}

pragma(inline, true)
int flushFile(Handle handle) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
}
do
{
    int result;
    do
    {
        result = fsync(handle);
    }
    while (result < 0 && errno == EINTR);
    return result;
}

pragma(inline, true)
long getLengthFile(Handle handle) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
}
do
{
    const curPosition = seekHandle(0, SeekOrigin.current);
    if (curPosition < 0)
        return curPosition;
    scope (exit)
        seekHandle(curPosition, SeekOrigin.begin);

    return seekHandle(0, SeekOrigin.end);
}

Handle openFile(scope const(char)[] fileName, scope const(StreamOpenInfo) openInfo) nothrow @trusted
{
    import std.internal.cstring : tempCString;

    auto lpFileName = fileName.tempCString();
    Handle result;
    do
    {
        result = open(lpFileName, openInfo.mode, openInfo.flag);
    }
    while (result < 0 && errno == EINTR);
    return result;
}

pragma(inline, true)
int readFile(Handle handle, scope ubyte[] bytes) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
    assert(bytes.length > 0);
    assert(bytes.length <= int.max);
}
do
{
    int result;
    do
    {
        result = read(handle, bytes.ptr, cast(uint)bytes.length);
    }
    while (result < 0 && errno == EINTR);
    return result;
}

int removeFile(scope const(char)[] fileName) nothrow @trusted
{
    import std.internal.cstring : tempCString;

    auto lpFileName = fileName.tempCString();
    int result;
    do
    {
        result = remove(lpFileName);
    }
    while (result < 0 && errno == EINTR);
    return result;
}

pragma(inline, true)
long seekFile(Handle handle, long offset, SeekOrigin origin) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
}
do
{
    long result;
    do
    {
        result = lseek64(handle, offset, origin);
    }
    while (result < 0 && errno == EINTR);
    return result;
}

pragma(inline, true)
int setLengthFile(Handle handle, long length) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
}
do
{
    int result;
    do
    {
        result = ftruncate64(handle, length);
    }
    while (result < 0 && errno == EINTR);
    return result;
}

pragma(inline, true)
int writeFile(Handle handle, scope const(ubyte)[] bytes) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
    assert(bytes.length >= 0);
    assert(bytes.length <= int.max);
}
do
{
    int result;
    do
    {
        result = write(handle, bytes.ptr, cast(uint)bytes.length);
    }
    while (result < 0 && errno == EINTR);
    return result;
}
