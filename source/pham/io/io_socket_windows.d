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

module pham.io.io_socket_windows;

version(Windows):

import core.sys.windows.winbase : GetComputerNameA;
import core.sys.windows.windef : DWORD, MAKEWORD;
import core.sys.windows.winsock2;
public import core.sys.windows.winsock2 : Linger = linger, TimeVal = timeval;

pragma(lib, "Iphlpapi.lib");
pragma(lib, "Ws2_32.lib");

extern (Windows) DWORD if_nametoindex(scope const char*) @nogc nothrow @trusted;
extern (Windows) void WSASetLastError(int) @nogc nothrow @trusted;

import pham.utl.utl_result : resultOK, resultError;
import pham.io.io_socket_type : SelectMode;

alias SocketHandle = SOCKET;
enum invalidSocketHandle = INVALID_SOCKET;
enum AI_V4MAPPED = 0x0800; // https://learn.microsoft.com/en-us/windows/win32/api/ws2def/ns-ws2def-addrinfoex4

struct WSAStartupResult
{
    WSADATA wsaData;
    int wsaErrorCode;
}

pragma(inline, true)
SocketHandle acceptSocket(SocketHandle handle, scope sockaddr* nameVal, scope int* nameLen) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return accept(handle, nameVal, nameLen);
}

pragma(inline, true)
int bindSocket(SocketHandle handle, scope const(sockaddr)* nameVal, int nameLen) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return bind(handle, nameVal, nameLen);
}

pragma(inline, true)
int closeSocket(SocketHandle handle) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return closesocket(handle);
}

pragma(inline, true)
int connectSocket(SocketHandle handle, scope const(sockaddr)* nameVal, int nameLen, bool blocking) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    const r = connect(handle, nameVal, nameLen);
    return r == 0 || blocking
        ? r
        : (lastSocketError() == WSAEWOULDBLOCK ? EINPROGRESS : r);
}

pragma(inline, true)
SocketHandle createSocket(int family, int type, int protocol) nothrow @trusted
{
    return socket(family, type, protocol);
}

pragma(inline, true)
int getAvailableBytesSocket(SocketHandle handle) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    enum FIONREAD = 0x4004667F;
    uint result;
    const r = ioctlsocket(handle, FIONREAD, &result);
    return r == 0 ? cast(int)result : r;
}

uint getComputerNameOS(scope return char[] buffer) @nogc nothrow @trusted
in
{
    assert(buffer.length > 1);
}
do
{
    DWORD size = cast(DWORD)(buffer.length - 1);
    if (GetComputerNameA(&buffer[0], &size))
        return size;

    return 0;
}

int getErrorSocket(SocketHandle handle) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    int optVal;
    const r = getIntOptionSocket!int(handle, SOL_SOCKET, SO_ERROR, optVal);
    if (r < 0)
        return r;

    WSASetLastError(optVal);
    return optVal ? resultOK : resultError;
}

pragma(inline, true)
int getIntOptionSocket(T)(SocketHandle handle, int optLevel, int optName, out T optVal) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    optVal = 0;
    int optLen = T.sizeof;
    return getsockopt(handle, optLevel, optName, &optVal, &optLen);
}

uint interfaceNameToIndex(scope const(char)[] scopeId) nothrow @trusted
{
    import std.internal.cstring : tempCString;

    auto lpscopeId = scopeId.tempCString();
    return if_nametoindex(lpscopeId);
}

pragma(inline, true)
int lastSocketError() nothrow @trusted
{
    return WSAGetLastError();
}

pragma(inline, true)
int listenSocket(SocketHandle handle, int backLog) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return listen(handle, backLog);
}

pragma(inline, true)
int receiveSocket(SocketHandle handle, scope ubyte[] bytes, int flags) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    const len = cast(int)bytes.length;
    return recv(handle, len ? &bytes[0] : null, len, flags);
}

int selectSocket(SocketHandle handle, SelectMode modes, TimeVal timeout) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    const isRead = (modes & SelectMode.read) == SelectMode.read;
    const isWrite = (modes & SelectMode.write) == SelectMode.write;
    const isError = (modes & SelectMode.error) == SelectMode.error;

    fd_set readSet, writeSet, errorSet;
    if (isRead)
    {
        FD_ZERO(&readSet);
        FD_SET(handle, &readSet);
    }
    if (isWrite)
    {
        FD_ZERO(&writeSet);
        FD_SET(handle, &writeSet);
    }
    if (isError)
    {
        FD_ZERO(&errorSet);
        FD_SET(handle, &errorSet);
    }

    const r = select(0 /*Not used*/, isRead ? &readSet : null, isWrite ? &writeSet : null, isError ? &errorSet : null, &timeout);

    if (r <= 0)
    {
        if (r == 0)
            WSASetLastError(ETIMEDOUT);
        return resultError;
    }

    int result = 0;

    if (isRead && FD_ISSET(handle, &readSet))
        result |= SelectMode.read;

    if (isWrite && FD_ISSET(handle, &writeSet))
        result |= SelectMode.write;

    if (isError && FD_ISSET(handle, &errorSet))
    {
        result |= SelectMode.error;
        getErrorSocket(handle);
    }

    return result;
}

pragma(inline, true)
int sendSocket(SocketHandle handle, scope const(ubyte)[] bytes, int flags) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
    assert(bytes.length <= int.max);
}
do
{
    const len = cast(int)bytes.length;
    return send(handle, len ? &bytes[0] : null, len, flags);
}

pragma(inline, true)
int setBlockingSocket(SocketHandle handle, bool state) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    uint n = state ? 0 : 1;
    return ioctlsocket(handle, FIONBIO, &n); // FIONBIO = input/output non-blocking
}

pragma(inline, true)
int setIntOptionSocket(T)(SocketHandle handle, int optLevel, int optName, T optVal) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return setsockopt(handle, optLevel, optName, &optVal, T.sizeof);
}

pragma(inline, true)
int setLingerSocket(SocketHandle handle, Linger linger) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return setsockopt(handle, SOL_SOCKET, SO_LINGER, &linger, Linger.sizeof);
}

pragma(inline, true)
int setReadTimeoutSocket(SocketHandle handle, TimeVal timeout) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return setTimeoutSocket(handle, timeout, SO_RCVTIMEO);
}

pragma(inline, true)
private int setTimeoutSocket(SocketHandle handle, TimeVal timeout, int optionName) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return setsockopt(handle, SOL_SOCKET, optionName, &timeout, timeout.sizeof);
}

pragma(inline, true)
int setWriteTimeoutSocket(SocketHandle handle, TimeVal timeout) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return setTimeoutSocket(handle, timeout, SO_SNDTIMEO);
}

pragma(inline, true)
int shutdownSocket(SocketHandle handle, int reason) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return shutdown(handle, reason);
}

int waitForConnectSocket(SocketHandle handle, TimeVal timeout) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    const r = selectSocket(handle, SelectMode.waitforConnect, timeout);
    return r <= 0
        ? resultError
        : ((r & SelectMode.error) == SelectMode.error ? resultError : resultOK);
}

static immutable WSAStartupResult wsaStartupResult;


// Any below codes are private
private:

import core.attribute : standalone;

@standalone
shared static this() nothrow @trusted
{
    ushort wsaVersion = MAKEWORD(2, 2);
    WSADATA wsaData;
    wsaStartupResult.wsaErrorCode = WSAStartup(wsaVersion, &wsaData);
    wsaStartupResult.wsaData = cast(immutable)wsaData;

    //import std.stdio : writeln;
    //debug writeln("WSAStartup=", _wsaStartupResult, ", wsaVersion=", wsaVersion);
}

@standalone
shared static ~this() nothrow @trusted
{
    if (wsaStartupResult.wsaErrorCode == 0)
        WSACleanup();
}
