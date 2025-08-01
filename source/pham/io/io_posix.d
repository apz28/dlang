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

import core.stdc.errno;
import core.stdc.stdio : remove;
import core.sys.posix.fcntl;
import core.sys.posix.unistd : close, fsync, ftruncate64, lseek64, pipe, read, write;

import pham.io.io_type : SeekOrigin, StreamOpenInfo;

alias FileHandle = int;
enum errorIOResult = -1;
enum invalidFileHandle = -1;

pragma(inline, true)
bool canRetry(int apiResult, ref int limit) @nogc nothrow
{
    enum limitEINTR = 5;
    return apiResult == errorIOResult && errno == EINTR && limit++ < limitEINTR;
}

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
    while (canRetry(result, limit));
    inputHandle = handles[0];
    outputHandle = handles[1];
    return result;
}

pragma(inline, true)
int flushFile(FileHandle handle) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    int result, limit;
    do
    {
        result = fsync(handle);
    }
    while (canRetry(result, limit));
    return result;
}

pragma(inline, true)
long getLengthFile(FileHandle handle) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
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
    while (canRetry(result, limit));
    return result;
}

pragma(inline, true)
int readFile(FileHandle handle, scope ubyte[] bytes) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
    assert(bytes.length <= int.max);
}
do
{
    int result, limit;
    do
    {
        result = cast(int)read(handle, &bytes[0], bytes.length);
    }
    while (canRetry(result, limit));
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
    while (canRetry(result, limit));
    return result;
}

pragma(inline, true)
long seekFile(FileHandle handle, long offset, SeekOrigin origin) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    long result;
    int limit;
    do
    {
        result = lseek64(handle, offset, origin);
    }
    while (canRetry(cast(int)result, limit));
    return result;
}

pragma(inline, true)
int setLengthFile(FileHandle handle, long length) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    int result, limit;
    do
    {
        result = ftruncate64(handle, length);
    }
    while (canRetry(result, limit));
    return result;
}

pragma(inline, true)
int writeFile(FileHandle handle, scope const(ubyte)[] bytes) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
    assert(bytes.length <= int.max);
}
do
{
    int result, limit;
    do
    {
        result = cast(int)write(handle, &bytes[0], bytes.length);
    }
    while (canRetry(result, limit));
    return result;
}
