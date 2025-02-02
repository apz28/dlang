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

module pham.io.io_socket_posix;

version(Posix):

import core.sys.posix.fcntl : errno;
import core.sys.posix.net.if_;
import core.sys.posix.sys.ioctl;
import core.sys.posix.sys.select;
import core.sys.posix.sys.socket;
public import core.sys.posix.sys.socket : Linger = linger;
public import core.sys.posix.sys.time : TimeVal = timeval;
import core.sys.posix.unistd : close, gethostname;

import pham.utl.utl_result : resultError, resultOK;
import pham.io.io_socket_type : SelectMode;

enum IPV6_V6ONLY = 27;
alias SocketHandle = int;
enum invalidSocketHandle = -1;
private enum limitEINTR = 5;

pragma(inline, true)
SocketHandle acceptSocket(SocketHandle handle, scope sockaddr* nameVal, scope int* nameLen) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    SocketHandle result;
    int limit = 0;
    do
    {
        result = accept(handle, nameVal, nameLen);
    }
    while (result == invalidSocketHandle && errno == EINTR && limit++ < limitEINTR);
    return result;
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
    return close(handle);
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
        : (lastSocketError() == EINPROGRESS ? EINPROGRESS : r);
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
    int r, result, limit;
    do
    {
        r = ioctl(fd, FIONREAD, &result);
    }
    while (r < 0 && errno == EINTR && limit++ < limitEINTR);
    return r == 0 ? result : r;
}

pragma(inline, true)
int getBlockingSocket(SocketHandle handle) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    const r = fcntl(handle, F_GETFL, 0);
    return r < 0 ? r : ((r & O_NONBLOCK) == O_NONBLOCK ? 0 : 1);
}

uint getComputerNameOS(scope return char[] buffer) @nogc nothrow @trusted
in
{
    assert(buffer.length > 1);
}
do
{
    buffer[] = '\0';
    uint size = cast(uint)(buffer.length - 1);
    if (gethostname(&buffer[0], size) == 0)
    {
        foreach (i; 0..buffer.length)
        {
            if (buffer[i] == '\0')
                return cast(uint)i;
        }
    }

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

    errno = optVal;
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
    return errno;
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
    int r, limit;
    do
    {
        const len = cast(int)bytes.length;
        r = recv(handle, len ? &bytes[0] : null, len, flags);
    }
    while (r < 0 && errno == EINTR && limit++ < limitEINTR);
    return r;
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

    TimeVal selectTimeout;
    fd_set readSet, writeSet, errorSet;
    int r, limit;
    do
    {
        selectTimeout = timeout;

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

        r = select(handle+1, isRead ? &readSet : null, isWrite ? &writeSet : null, isError ? &errorSet : null, &selectTimeout);
    }
    while (r < 0 && errno == EINTR && limit++ < limitEINTR);

    if (r <= 0)
    {
        if (r == 0)
            errno = ETIMEDOUT;
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
    int r, limit;
    do
    {
        const len = cast(int)bytes.length;
        r = send(handle, len ? &bytes[0] : null, len, flags);
    }
    while (r < 0 && errno == EINTR && limit++ < limitEINTR);
    return r;
}

pragma(inline, true)
int setBlockingSocket(SocketHandle handle, bool state) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    int n = fcntl(handle, F_GETFL, 0);
    if (n == -1)
        return n;
    if (state)
        n &= ~O_NONBLOCK;
    else
        n |= O_NONBLOCK;
    return fcntl(handle, F_SETFL, n);
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
