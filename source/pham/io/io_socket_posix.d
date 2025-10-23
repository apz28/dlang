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

import core.stdc.errno;
import core.sys.posix.fcntl;
import core.sys.posix.net.if_;
import core.sys.posix.poll;
import core.sys.posix.sys.ioctl;
import core.sys.posix.sys.select;
import core.sys.posix.sys.socket;
import core.sys.posix.sys.time : timeval;
import core.sys.posix.unistd : close, gethostname;

import pham.utl.utl_result : ResultCode;
import pham.io.io_socket_type : PollFDSet, PollResult,
    SelectFDSet, SelectMode, SocketOptionItem, SocketOptionItems,
    isSelectMode, toSocketTimeMSecs;

alias FDSet = fd_set;
alias Linger = linger;
alias PollFD = pollfd;
alias SocketHandle = int;
alias TimeVal = timeval;

enum : int
{
    SD_RECEIVE = SHUT_RD,
    SD_SEND    = SHUT_WR,
    SD_BOTH    = SHUT_RDWR,
}

enum : int
{
    SO_USELOOPBACK = 0x0040,
}

enum errorSocketResult = -1;
enum invalidSocketHandle = -1;
enum POLLRead = POLLRDNORM | POLLRDBAND;
enum POLLWrite = POLLWRNORM | POLLWRBAND;

enum eHandleReset = 10054;
enum eInvalidHandle = 6;
enum eTimeout = 10060;

pragma(inline, true)
SocketHandle acceptSocket(SocketHandle handle, scope sockaddr* nameVal, scope socklen_t* nameLen) nothrow @trusted
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
    while (canRetry(result, limit));
    return result;
}

pragma(inline, true)
int bindSocket(SocketHandle handle, scope const(sockaddr)* nameVal, socklen_t nameLen) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    return bind(handle, nameVal, nameLen);
}

private enum limitEINTR = 5;
pragma(inline, true)
bool canRetry(int apiResult, ref int limit) @nogc nothrow
{
    return apiResult == errorSocketResult && errno == EINTR && limit++ < limitEINTR;
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
int connectSocket(SocketHandle handle, scope const(sockaddr)* nameVal, socklen_t nameLen, bool blocking) nothrow @trusted
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
    auto result = socket(family, type, protocol);
    if (result != invalidSocketHandle)
        ignoreSIGPIPE(result);
    return result;
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
        r = ioctl(handle, FIONREAD, &result);
    }
    while (canRetry(r, limit));
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

uint getComputerNameOS(return scope char[] buffer) @nogc nothrow @trusted
in
{
    assert(buffer.length > 1);
}
do
{
    buffer[] = '\0';
    auto size = cast(socklen_t)(buffer.length - 1);
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

pragma(inline, true)
int getOptionSocket(T)(SocketHandle handle, scope const(SocketOptionItem) optInd, out T optVal) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    optVal = T.init;
    socklen_t optLen = T.sizeof;
    return getsockopt(handle, optInd.level, optInd.name, &optVal, &optLen);
}

int getReadTimeoutSocket(SocketHandle handle, out TimeVal timeout) nothrow @trusted
{
    return getOptionSocket!TimeVal(handle, SocketOptionItems.receiveTimeout, timeout);
}

int getWriteTimeoutSocket(SocketHandle handle, out TimeVal timeout) nothrow @trusted
{
    return getOptionSocket!TimeVal(handle, SocketOptionItems.sendTimeout, timeout);
}

int ignoreSIGPIPE(SocketHandle handle) nothrow @trusted
{
    static if (is(typeof(SO_NOSIGPIPE)))
    {
        auto option = SocketOptionItem(SOL_SOCKET, SO_NOSIGPIPE);
        return setOptionSocket!int(handle, option, 1);
    }
    else
        return 0;
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
int lastSocketError(int errorCode) nothrow @trusted
{
    errno = errorCode;
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
    return r != errorSocketResult ? optVal : errno;
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
    int r, limit;
    do
    {
        r = poll(&pollSets.pollFDs[0], length, toSocketTimeMSecs(timeout));
    }
    while (canRetry(r, limit));

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
        return ResultCode.error;
    }
    else
        return ResultCode.ok;
}

pragma(inline, true)
int receiveSocket(SocketHandle handle, scope ubyte[] bytes, int flags) nothrow @trusted
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
        r = cast(int)recv(handle, len ? &bytes[0] : null, len, flags);
    }
    while (canRetry(r, limit));
    return r;
}

int selectSocket(ref SelectFDSet selectSets, TimeVal timeout) nothrow @trusted
{
    int r, limit;
    do
    {
        r = select(selectSets.nfds + 1,
            selectSets.readSetCount ? &selectSets.readSet : null,
            selectSets.writeSetCount ? &selectSets.writeSet : null,
            selectSets.errorSetCount ? &selectSets.errorSet : null,
            &timeout);
    }
    while (canRetry(r, limit));

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

int selectSocket(SocketHandle handle, SelectMode queryModes, TimeVal timeout, out SelectMode resultModes) nothrow @safe
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
        return ResultCode.error;
    }
    else
        return ResultCode.ok;
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
        r = cast(int)send(handle, len ? &bytes[0] : null, len, flags);
    }
    while (canRetry(r, limit));
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
    if (n == errorSocketResult)
        return n;
    if (state)
        n &= ~O_NONBLOCK;
    else
        n |= O_NONBLOCK;
    return fcntl(handle, F_SETFL, n);
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
    auto optInd = SocketOptionItems.receiveTimeout;
    return setsockopt(handle, optInd.level, optInd.name, &timeout, TimeVal.sizeof);
}

pragma(inline, true)
int setWriteTimeoutSocket(SocketHandle handle, TimeVal timeout) nothrow @trusted
in
{
    assert(handle != invalidSocketHandle);
}
do
{
    auto optInd = SocketOptionItems.sendTimeout;
    return setsockopt(handle, optInd.level, optInd.name, &timeout, TimeVal.sizeof);
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
    return resultModes & SelectMode.error ? ResultCode.error : ResultCode.ok;
}
