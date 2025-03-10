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

module pham.io.io_posix;

version(Posix):

import core.sys.posix.fcntl;
import core.sys.posix.unistd : close, lseek64, pipe, read, ftruncate64, write;
import core.stdc.stdio : remove;

import pham.io.io_type : SeekOrigin, StreamOpenInfo;

alias FileHandle = int;
enum invalidFileHandle = -1;
private enum limitEINTR = 5;

pragma(inline, true)
int closeFile(FileHandle handle) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    return close(handle);
}

int createFilePipes(const(bool) asInput, out FileHandle inputHandle, out FileHandle outputHandle,
    uint bufferSize = 0) nothrow @trusted
{
    FileHandle[2] handles = invalidFileHandle;
    int result, limit;
    do
    {
        result = pipe(handles);
    }
    while (result < 0 && errno == EINTR && limit++ < limitEINTR);
    inputHandle = handles[0];
    outputHandle = handles[1];
    return result;
}

pragma(inline, true)
int flushFile(FileHandle handle) nothrow @trusted
in
{
    assert(handle != invalidHandle);
}
do
{
    int result, limit;
    do
    {
        result = fsync(handle);
    }
    while (result < 0 && errno == EINTR && limit++ < limitEINTR);
    return result;
}

pragma(inline, true)
long getLengthFile(FileHandle handle) nothrow @trusted
in
{
    assert(handle != invalidHandle);
}
do
{
    const curPosition = seekFile(handle, 0, SeekOrigin.current);
    if (curPosition < 0)
        return curPosition;
    scope (exit)
        seekFile(handle, curPosition, SeekOrigin.begin);

    return seekFile(handle, 0, SeekOrigin.end);
}

FileHandle openFile(scope const(char)[] fileName, scope const(StreamOpenInfo) openInfo) nothrow @trusted
{
    import std.internal.cstring : tempCString;

    auto lpFileName = fileName.tempCString();
    FileHandle result;
    int limit;
    do
    {
        result = open(lpFileName, openInfo.mode, openInfo.flag);
    }
    while (result < 0 && errno == EINTR && limit++ < limitEINTR);
    return result;
}

pragma(inline, true)
int readFile(FileHandle handle, scope ubyte[] bytes) nothrow @trusted
in
{
    assert(handle != invalidHandle);
    assert(bytes.length > 0);
    assert(bytes.length <= int.max);
}
do
{
    int result, limit;
    do
    {
        result = read(handle, bytes.ptr, cast(uint)bytes.length);
    }
    while (result < 0 && errno == EINTR && limit++ < limitEINTR);
    return result;
}

int removeFile(scope const(char)[] fileName) nothrow @trusted
{
    import std.internal.cstring : tempCString;

    auto lpFileName = fileName.tempCString();
    int result, limit;
    do
    {
        result = remove(lpFileName);
    }
    while (result < 0 && errno == EINTR && limit++ < limitEINTR);
    return result;
}

pragma(inline, true)
long seekFile(FileHandle handle, long offset, SeekOrigin origin) nothrow @trusted
in
{
    assert(handle != invalidHandle);
}
do
{
    long result;
    int limit;
    do
    {
        result = lseek64(handle, offset, origin);
    }
    while (result < 0 && errno == EINTR && limit++ < limitEINTR);
    return result;
}

pragma(inline, true)
int setLengthFile(FileHandle handle, long length) nothrow @trusted
in
{
    assert(handle != invalidHandle);
}
do
{
    int result, limit;
    do
    {
        result = ftruncate64(handle, length);
    }
    while (result < 0 && errno == EINTR && limit++ < limitEINTR);
    return result;
}

pragma(inline, true)
int writeFile(FileHandle handle, scope const(ubyte)[] bytes) nothrow @trusted
in
{
    assert(handle != invalidHandle);
    assert(bytes.length >= 0);
    assert(bytes.length <= int.max);
}
do
{
    int result, limit;
    do
    {
        result = write(handle, bytes.ptr, cast(uint)bytes.length);
    }
    while (result < 0 && errno == EINTR && limit++ < limitEINTR);
    return result;
}
