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

enum eHandleReset = WSAECONNRESET; // 10054
enum eInvalidHandle = 6; // WSA_INVALID_HANDLE=6
enum eTimeout = ETIMEDOUT; // 10060

// Not found in core.sys.windows.winsock2, so declare it here
// https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-wsapoll
// events
enum POLLPRI    = 0x0400;
enum POLLRDBAND = 0x0200;
enum POLLRDNORM = 0x0100;
enum POLLIN     = POLLRDNORM | POLLRDBAND;
enum POLLWRBAND = 0x0020;
enum POLLWRNORM = 0x0010;
enum POLLOUT    = POLLWRNORM;
enum POLLRead   = POLLRDNORM | POLLRDBAND;
enum POLLWrite  = POLLWRNORM | POLLWRBAND;

// revents
enum POLLERR  = 0x0001;
enum POLLHUP  = 0x0002;
enum POLLNVAL = 0x0004;
//enum POLLPRI    = 0x0400;
//enum POLLRDBAND = 0x0200;
//enum POLLRDNORM = 0x0100;
//enum POLLWRBAND = 0x0020;
//enum POLLWRNORM = 0x0010;

struct pollfd
{
    SOCKET fd;
    short events; // query status mask
    short revents; // result status mask
}

extern (Windows) DWORD if_nametoindex(scope const char* interfaceName) @nogc nothrow; // Iphlpapi.lib
extern (Windows) int WSAPoll(pollfd* fdArray, uint fds, int timeout) @nogc nothrow; // Ws2_32.lib
    // timeout = "> 0"=The time, in milliseconds, to wait; "= 0"=Return immediately; "< 0"= wait indefinitely
extern (Windows) void WSASetLastError(int iError) @nogc nothrow; // Ws2_32.lib

import pham.utl.utl_result : resultOK, resultError;
import pham.io.io_socket_type : isSelectMode, PollFDSet, PollResult,
    SelectFDSet, SelectMode, SocketOptionItem, SocketOptionItems, toSocketTimeMSecs, toSocketTimeVal;

alias SocketHandle = SOCKET;

enum errorSocketResult = SOCKET_ERROR;
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

pragma(inline, true)
int getOptionSocket(T)(SocketHandle handle, scope const(SocketOptionItem) optInd, out T optVal) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    optVal = 0;
    int optLen = T.sizeof;
    return getsockopt(handle, optInd.level, optInd.name, &optVal, &optLen);
}

int getReadTimeoutSocket(SocketHandle handle, out TimeVal timeout) nothrow @trusted
{
    int msecs;
    const r = getOptionSocket!int(handle, SocketOptionItems.receiveTimeout, msecs);
    timeout = r != errorSocketResult ? toSocketTimeVal(cast(uint)msecs) : TimeVal.init;
    return r;
}

int getWriteTimeoutSocket(SocketHandle handle, out TimeVal timeout) nothrow @trusted
{
    int msecs;
    const r = getOptionSocket!int(handle, SocketOptionItems.sendTimeout, msecs);
    timeout = r != errorSocketResult ? toSocketTimeVal(cast(uint)msecs) : TimeVal.init;
    return r;
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
int lastSocketError(int errorCode) nothrow @trusted
{
    WSASetLastError(errorCode);
    return errorCode;
}

int lastSocketErrorOf(SocketHandle handle) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    int optVal;
    const r = getOptionSocket!int(handle, SocketOptionItems.error, optVal);
    return r != errorSocketResult ? optVal : WSAGetLastError();
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
short pollEventOf(const(SelectMode) modes) @nogc nothrow pure @safe
{
    short result = 0;
    if (isSelectMode(modes, SelectMode.read))
        result |= POLLRead;
    if (isSelectMode(modes, SelectMode.write))
        result |= POLLWrite;
    return result;
}

int pollSocket(ref PollFDSet pollSets, TimeVal timeout) nothrow @trusted
{
    const length = pollSets.length;
    const r = WSAPoll(&pollSets.pollFDs[0], length, toSocketTimeMSecs(timeout));
    pollSets.pollResults.length = length;
    if (r > 0)
    {
        foreach (i; 0..length)
        {
            const revents = pollSets.pollFDs[i].revents;
            if (revents & POLLERR)
                pollSets.pollResults[i] = PollResult(SelectMode.error, lastSocketErrorOf(pollSets.pollFDs[i].fd));
            else if (revents & POLLHUP)
                pollSets.pollResults[i] = PollResult(SelectMode.error, eHandleReset);
            else if (revents & POLLNVAL)
                pollSets.pollResults[i] = PollResult(SelectMode.error, eInvalidHandle);
            else
            {
                SelectMode resultModes = SelectMode.none;
                if (revents & (POLLRead | POLLPRI))
                    resultModes |= SelectMode.read;
                if (revents & POLLWrite)
                    resultModes |= SelectMode.write;
                pollSets.pollResults[i] = PollResult(resultModes, 0);
            }
        }
    }
    else if (r == 0)
        pollSets.pollResults[] = PollResult(SelectMode.error, eTimeout);
    else
        pollSets.pollResults[] = PollResult(SelectMode.error, lastSocketError());

    return r;
}

int pollSocket(SocketHandle handle, SelectMode queryModes, TimeVal timeout, out SelectMode resultModes) nothrow
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    PollFDSet pollSets;
    pollSets.add(handle, queryModes);
    pollSocket(pollSets, timeout);
    resultModes = pollSets.pollResults[0].modes;
    if (isSelectMode(resultModes, SelectMode.error))
    {
        lastSocketError(pollSets.pollResults[0].errorCode);
        return resultError;
    }
    else
        return resultOK;
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

int selectSocket(ref SelectFDSet selectSets, TimeVal timeout) nothrow @trusted
{
    const r = select(0 /*Not used*/,
        selectSets.readSetCount ? &selectSets.readSet : null,
        selectSets.writeSetCount ? &selectSets.writeSet : null,
        selectSets.errorSetCount ? &selectSets.errorSet : null,
        &timeout);
    selectSets.pollResults.length = selectSets.length;
    if (r > 0)
    {
        foreach (i, ref fd; selectSets.pollFDs)
        {
            SelectMode resultModes = SelectMode.none;
            int resultErrorCode = 0;
            if (isSelectMode(fd.modes, SelectMode.read) && FD_ISSET(fd.handle, &selectSets.readSet))
                resultModes |= SelectMode.read;
            if (isSelectMode(fd.modes, SelectMode.write) && FD_ISSET(fd.handle, &selectSets.writeSet))
                resultModes |= SelectMode.write;
            if (isSelectMode(fd.modes, SelectMode.error) && FD_ISSET(fd.handle, &selectSets.errorSet))
            {
                resultModes |= SelectMode.error;
                resultErrorCode = lastSocketErrorOf(fd.handle);
            }
            selectSets.pollResults[i] = PollResult(resultModes, resultErrorCode);
        }
    }
    else if (r == 0)
        selectSets.pollResults[] = PollResult(SelectMode.error, eTimeout);
    else
        selectSets.pollResults[] = PollResult(SelectMode.error, lastSocketError());

    return r;
}

int selectSocket(SocketHandle handle, SelectMode queryModes, TimeVal timeout, out SelectMode resultModes) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    SelectFDSet selectSets;
    selectSets.add(handle, queryModes);
    selectSocket(selectSets, timeout);
    resultModes = selectSets.pollResults[0].modes;
    if (isSelectMode(resultModes, SelectMode.error))
    {
        lastSocketError(selectSets.pollResults[0].errorCode);
        return resultError;
    }
    else
        return resultOK;
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
int setOptionSocket(T)(SocketHandle handle, scope const(SocketOptionItem) optInd, T optVal) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return setsockopt(handle, optInd.level, optInd.name, &optVal, T.sizeof);
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
    return setOptionSocket(handle, SocketOptionItems.receiveTimeout, toSocketTimeMSecs(timeout));
}

pragma(inline, true)
int setWriteTimeoutSocket(SocketHandle handle, TimeVal timeout) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return setOptionSocket(handle, SocketOptionItems.sendTimeout, toSocketTimeMSecs(timeout));
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

int waitForConnectSocket(SocketHandle handle, TimeVal timeout) nothrow @safe
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    SelectMode resultModes;
    selectSocket(handle, SelectMode.waitforConnect, timeout, resultModes);
    return resultModes & SelectMode.error ? resultError : resultOK;
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
