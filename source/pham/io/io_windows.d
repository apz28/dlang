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

module pham.io.io_windows;

version(Windows):

import core.sys.windows.basetsd : HANDLE;
import core.sys.windows.winbase : CloseHandle, CreateFileW, CreatePipe, DeleteFileW, GetFileSizeEx, GetLastError,    
    HANDLE_FLAG_INHERIT, INVALID_HANDLE_VALUE, INVALID_SET_FILE_POINTER,
    ReadFile, SetEndOfFile, SetFilePointer, SetHandleInformation, SetLastError, WriteFile;
import core.sys.windows.windef : BOOL;
import core.sys.windows.winerror : NO_ERROR;
import core.sys.windows.winnt : LARGE_INTEGER, SECURITY_ATTRIBUTES;

pragma(lib, "kernel32");
extern (Windows) BOOL FlushFileBuffers(HANDLE hFile) @nogc nothrow @system;
//extern (Windows) DWORD GetFileType(HANDLE hFile) @nogc nothrow @system;

import pham.utl.utl_result : ResultCode;
import pham.io.io_type : SeekOrigin, StreamOpenInfo;

alias FileHandle = HANDLE;
alias invalidFileHandle = INVALID_HANDLE_VALUE;

/// Follow Posix return convention = -1=error, 0=success
pragma(inline, true)
int closeFile(FileHandle handle) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    return CloseHandle(handle) ? ResultCode.ok : ResultCode.error;
}

/// Follow Posix return convention = -1=error, 0=success
int createFilePipes(const(bool) asInput, out FileHandle inputHandle, out FileHandle outputHandle,
    uint bufferSize = 0) nothrow @trusted
{
    SECURITY_ATTRIBUTES saAttr;
    saAttr.nLength = SECURITY_ATTRIBUTES.sizeof;
    saAttr.bInheritHandle = true;
    saAttr.lpSecurityDescriptor = null;

    inputHandle = outputHandle = invalidFileHandle;
    int result = CreatePipe(&inputHandle, &outputHandle, &saAttr, bufferSize)
        ? ResultCode.ok
        : ResultCode.error;
    if (result == ResultCode.ok)
    {
        if (asInput)
        {
            if (!SetHandleInformation(outputHandle, HANDLE_FLAG_INHERIT, 0))
                result = ResultCode.error;
        }
        else
        {
            if (!SetHandleInformation(inputHandle, HANDLE_FLAG_INHERIT, 0))
                result = ResultCode.error;
        }
        if (result == ResultCode.error)
        {
            const e = GetLastError();
            CloseHandle(inputHandle);
            CloseHandle(outputHandle);
            SetLastError(e);
        }
    }
    return result;
}

/// Follow Posix return convention = -1=error, 0=success
pragma(inline, true)
int flushFile(FileHandle handle) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    return FlushFileBuffers(handle) ? ResultCode.ok : ResultCode.error;
}

/// Follow Posix return convention = -1=error, >=0=success with its length
pragma(inline, true)
long getLengthFile(FileHandle handle) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    LARGE_INTEGER li;
    return GetFileSizeEx(handle, &li) ? li.QuadPart : ResultCode.error;
}

FileHandle openFile(scope const(char)[] fileName, scope const(StreamOpenInfo) openInfo) nothrow @trusted
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

/// Follow Posix return convention = -1=error, >=0=success with its read length
pragma(inline, true)
int readFile(FileHandle handle, scope ubyte[] bytes) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
    assert(bytes.length > 0);
    assert(bytes.length <= int.max);
}
do
{
    uint result = 0;
    return ReadFile(handle, cast(void*)bytes.ptr, cast(uint)bytes.length, &result, null)
        ? cast(int)result
        : ResultCode.error;
}

/// Follow Posix return convention = -1=error, 0=success
int removeFile(scope const(char)[] fileName) nothrow @trusted
{
    import std.internal.cstring : tempCStringW;

    auto lpFileName = fileName.tempCStringW();
    return DeleteFileW(lpFileName) ? ResultCode.ok : ResultCode.error;
}

/// Follow Posix return convention = -1=error, >=0=success with its seek position
pragma(inline, true)
long seekFile(FileHandle handle, long offset, SeekOrigin origin) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    LARGE_INTEGER li;
    li.QuadPart = offset;
    li.LowPart = SetFilePointer(handle, li.LowPart, &li.HighPart, origin);
    return li.LowPart == INVALID_SET_FILE_POINTER && GetLastError() != NO_ERROR
        ? ResultCode.error
        : li.QuadPart;
}

/// Follow Posix return convention = -1=error, >=0=success with its file length
pragma(inline, true)
int setLengthFile(FileHandle handle, long length) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
}
do
{
    return SetEndOfFile(handle) ? ResultCode.ok : ResultCode.error;
}

/// Follow Posix return convention = -1=error, >=0=success with its written length
pragma(inline, true)
int writeFile(FileHandle handle, scope const(ubyte)[] bytes) nothrow @trusted
in
{
    assert(handle != invalidFileHandle);
    assert(bytes.length >= 0);
    assert(bytes.length <= int.max);
}
do
{
    uint result = 0;
    return WriteFile(handle, cast(void*)bytes.ptr, cast(uint)bytes.length, &result, null)
        ? cast(int)result
        : ResultCode.error;
}
