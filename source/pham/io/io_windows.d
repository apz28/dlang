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

module pham.io.windows;

version (Windows):

import core.sys.windows.basetsd : HANDLE;
import core.sys.windows.winbase : CloseHandle, CreateFileW, CreatePipe, DeleteFileW, GetFileSizeEx,
    GetLastError,
    HANDLE_FLAG_INHERIT, INVALID_HANDLE_VALUE, INVALID_SET_FILE_POINTER,
    ReadFile, SetEndOfFile, SetFilePointer, SetHandleInformation, SetLastError, WriteFile;
import core.sys.windows.windef : BOOL;
import core.sys.windows.winerror : NO_ERROR;
import core.sys.windows.winnt : LARGE_INTEGER, SECURITY_ATTRIBUTES;

pragma(lib, "kernel32");
extern (Windows) BOOL FlushFileBuffers(HANDLE hFile) @nogc nothrow @system;
//extern (Windows) DWORD GetFileType(HANDLE hFile) @nogc nothrow @system;

import pham.io.type : SeekOrigin, StreamOpenInfo, StreamResult;

alias Handle = HANDLE;
alias invalidHandleValue = INVALID_HANDLE_VALUE;

string getSystemErrorMessage(const(int) errorNo) nothrow @trusted
in
{
    assert(errorNo != 0);
}
do
{
    import core.sys.windows.winbase : FormatMessageA, FORMAT_MESSAGE_FROM_SYSTEM, FORMAT_MESSAGE_IGNORE_INSERTS;

    char[1_000] buf = void;
    const n = FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, null, errorNo, 0, buf.ptr, buf.length, null);
    return n > 0 ? buf[0..n].idup : null;
}

pragma(inline, true)
int lastErrorNo() nothrow @safe
{
    return cast(int)GetLastError();
}

pragma(inline, true)
int closeFile(Handle handle) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
}
do
{
    return CloseHandle(handle) ? StreamResult.success : StreamResult.failed;
}

int createFilePipes(const(bool) asInput, out Handle inputHandle, out Handle outputHandle,
    uint bufferSize = 0) nothrow @trusted
{
    SECURITY_ATTRIBUTES saAttr;
    saAttr.nLength = SECURITY_ATTRIBUTES.sizeof;
    saAttr.bInheritHandle = true;
    saAttr.lpSecurityDescriptor = null;

    inputHandle = invalidHandleValue;
    outputHandle = invalidHandleValue;
    int result = CreatePipe(&inputHandle, &outputHandle, &saAttr, bufferSize)
        ? StreamResult.success
        : StreamResult.failed;
    if (result == StreamResult.success)
    {
        if (asInput)
        {
            if (!SetHandleInformation(outputHandle, HANDLE_FLAG_INHERIT, 0))
                result = StreamResult.failed;
        }
        else
        {
            if (!SetHandleInformation(inputHandle, HANDLE_FLAG_INHERIT, 0))
                result = StreamResult.failed;
        }
        if (result == StreamResult.failed)
        {
            const e = GetLastError();
            CloseHandle(inputHandle);
            CloseHandle(outputHandle);
            SetLastError(e);
        }
    }
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
    return FlushFileBuffers(handle) ? StreamResult.success : StreamResult.failed;
}

pragma(inline, true)
long getLengthFile(Handle handle) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
}
do
{
    LARGE_INTEGER li;
    return GetFileSizeEx(handle, &li) ? li.QuadPart : StreamResult.failed;
}

Handle openFile(scope const(char)[] fileName, scope const(StreamOpenInfo) openInfo) nothrow @trusted
{
    import std.internal.cstring : tempCStringW;

    auto lpFileName = fileName.tempCStringW();
    return CreateFileW(
        lpFileName, // lpFileName
        openInfo.toDesiredAccess(), // dwDesiredAccess
        openInfo.toShareMode(), // dwShareMode
        null, // lpSecurityAttributes,
        openInfo.toCreationDisposition(), // dwCreationDisposition,
        openInfo.toFlagsAndAttributes(), // dwFlagsAndAttributes,
        null //hTemplateFile
        );
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
    uint result = 0;
    return ReadFile(handle, cast(void*)bytes.ptr, cast(uint)bytes.length, &result, null)
        ? cast(int)result
        : StreamResult.failed;
}

int removeFile(scope const(char)[] fileName) nothrow @trusted
{
    import std.internal.cstring : tempCStringW;

    auto lpFileName = fileName.tempCStringW();
    return DeleteFileW(lpFileName) ? StreamResult.success : StreamResult.failed;
}

pragma(inline, true)
long seekFile(Handle handle, long offset, SeekOrigin origin) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
}
do
{
    LARGE_INTEGER li;
    li.QuadPart = offset;
    li.LowPart = SetFilePointer(handle, li.LowPart, &li.HighPart, origin);
    return li.LowPart == INVALID_SET_FILE_POINTER && GetLastError() != NO_ERROR
        ? StreamResult.failed
        : li.QuadPart;
}

pragma(inline, true)
int setLengthFile(Handle handle, long length) nothrow @trusted
in
{
    assert(handle != invalidHandleValue);
}
do
{
    return SetEndOfFile(handle) ? StreamResult.success : StreamResult.failed;
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
    uint result = 0;
    return WriteFile(handle, cast(void*)bytes.ptr, cast(uint)bytes.length, &result, null)
        ? cast(int)result
        : StreamResult.failed;
}
