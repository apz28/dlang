/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.io.io_socket_epoll_windows;

version(Windows):

import core.sys.windows.winerror : ERROR_ALREADY_EXISTS;
import core.sys.windows.winsock2;
import std.algorithm : remove;

import pham.utl.utl_result : ResultCode;
import pham.io.io_socket_windows;

enum // EPOLL_EVENTS - Posix
{
    EPOLLIN = 0x001,
    EPOLLPRI = 0x002,
    EPOLLOUT = 0x004,
    EPOLLRDNORM = 0x040,
    EPOLLRDBAND = 0x080,
    EPOLLWRNORM = 0x100,
    EPOLLWRBAND = 0x200,
    EPOLLMSG = 0x400,
    EPOLLERR = 0x008,
    EPOLLHUP = 0x010,
    EPOLLRDHUP = 0x2000,

    EPOLLEXCLUSIVE = 1u << 28,
    EPOLLWAKEUP = 1u << 29,
    EPOLLONESHOT = 1u << 30,
    EPOLLET = 1u << 31
}

/**
 * Valid opcodes ( "op" parameter ) to issue to epoll_ctl() - Posix
 */
enum // EPOLL_CTL
{
    EPOLL_CTL_ADD = 1,	/* Add a file descriptor to the interface. */
    EPOLL_CTL_DEL = 2,	/* Remove a file descriptor from the interface. */
    EPOLL_CTL_MOD = 3,	/* Change file descriptor epoll_event structure. */
    EPOLL_CTL_LER = 4, /* Extended code to return last error number */
}

union EPollData
{
    void* ptr;
    SocketHandle fd;
    uint u32;
    ulong u64;
}
alias epoll_data = EPollData;
alias epoll_data_t = EPollData;

struct EPollEvent
{
    uint events;
    EPollData data;
}
alias epoll_event = EPollEvent;

struct EPollEventEx
{
    SocketHandle fd;
    WSANETWORKEVENTS events;
    EPollData data;
}

/**
 * Creates an epoll instance. Returns an fd for the new instance.
 * Params:
 *  size = a hint specifying the number of file descriptors to be associated with the new instance.
 * Returns:
 *  -1 = an error taken place
 *  0 = never returns such value
 *  > 0 = newly create epoll instance
 * Notes:
 *  The fd returned by epoll_create() should be closed with epoll_close().
 */
int epoll_create(int size) nothrow @safe
{
    return epollCreate(size, 0);
}

/**
 * Same as epoll_create but with an FLAGS parameter with "size" parameter set to 1.
 */
int epoll_create1(int flags) nothrow @safe
{
    return epollCreate(1, flags);
}

/**
 * Manipulate an epoll instance "epfd"
 * Params:
 *  epfd = epoll descriptor created by epoll_create or epoll_create1
 *  op = is one of the EPOLL_CTL_* constants defined above
 *  fd = is socket handle which the target of the operation
 *  event = describes which events the caller is interested in and any associated user data
 * Returns:
 *  0 = success
 *  -1 = error and WSAGetLastError function call will return the specific error code
 */
int epoll_ctl(int epfd, int op, SocketHandle fd, epoll_event* event) nothrow
{
    if (event is null && (op == EPOLL_CTL_ADD || op == EPOLL_CTL_MOD || op == EPOLL_CTL_LER))
    {
        lastSocketError(WSAEINVAL);
        return ResultCode.error;
    }

    switch (op)
    {
        case EPOLL_CTL_DEL:
            EPollEvent dump;
            return epoll_ctl_ex(epfd, op, fd, dump);

        case EPOLL_CTL_ADD:
        case EPOLL_CTL_MOD:
            EPollEvent evAddMod = *event;
            evAddMod.events = toWaitMask(evAddMod.events);
            return epoll_ctl_ex(epfd, op, fd, evAddMod);

        case EPOLL_CTL_LER:
            return epoll_ctl_ex(epfd, op, fd, *event);

        default:
            lastSocketError(WSAEINVAL);
            return ResultCode.error;
    }
}

/**
 * Same as epoll_ctl except event.events is actual FD_XXX network events
 */
int epoll_ctl_ex(int epfd, int op, SocketHandle fd, ref EPollEvent event) nothrow @trusted
{
    if (fd == invalidSocketHandle)
    {
        lastSocketError(WSAEBADF);
        return ResultCode.error;
    }

    auto lock = RAIIMutex(mutex);

    if (auto data = epfd in epfdData)
    {
        switch (op)
        {
            case EPOLL_CTL_ADD:
                return data.addEvent(fd, event);

            case EPOLL_CTL_DEL:
                return data.deleteEvent(fd);

            case EPOLL_CTL_MOD:
                return data.changeEvent(fd, event);

            case EPOLL_CTL_LER:
                return data.getLastErrorNumber(fd, event);

            default:
                lastSocketError(WSAEINVAL);
                return ResultCode.error;
        }
    }

    lastSocketError(WSAEBADF);
    return ResultCode.error;
}

/**
 * Wait for events on an epoll instance "epfd". Returns the number of
 * triggered events. Or -1 in case of error. The "WSAGetLastError()" function call will return the
 * specific error code.
 * Params:
 *  epfd = epoll descriptor created by epoll_create or epoll_create1
 *  events = is a buffer that will contain triggered events.
 *  maxEvents = is the maximum number of events to be returned (usually length of "events").
 *  timeout = specifies the maximum wait time in milliseconds (-1 == infinite).
 * Returns:
 *  0 = No event taken place, can be timeout
 *  -1 = error and WSAGetLastError function call will return the specific error code
 *  > 0 = number of triggered events
 */
int epoll_wait(int epfd, epoll_event* events, int maxEvents, int timeout) nothrow
{
    if (events is null || maxEvents < 1)
    {
        lastSocketError(WSAEINVAL);
        return ResultCode.error;
    }

    auto resultEventExs = new EPollEventEx[](maxEvents);
    const r = epoll_wait_ex(epfd, resultEventExs, timeout);
    if (r > 0)
    {
        auto resultEvents = events[0..maxEvents];
        foreach (i, ref re; resultEventExs)
        {
            if (i == maxEvents)
                break;

            resultEvents[i] = toPollEvent(re);
        }
    }
    return r;
}

/**
 * Same as epoll_wait except that "events" is D-safe parameter and contains specific
 * to Windows api result
 */
int epoll_wait_ex(int epfd, ref EPollEventEx[] events, int timeout) nothrow @trusted
{
    EPollSocketFD[] waitEvents;
    WSAEVENT[] waitHandles;
    {
        auto lock = RAIIMutex(mutex);

        if (auto data = epfd in epfdData)
            data.prepareWaitEvent(waitEvents, waitHandles);
        else
        {
            lastSocketError(WSAEBADF);
            return ResultCode.error;
        }
    }
    assert(waitEvents.length == waitHandles.length);

    if (waitHandles.length == 0)
        return 0;

    const wsaResult = WSAWaitForMultipleEvents(cast(uint)waitHandles.length, &waitHandles[0], false, timeout, false);
    if (wsaResult == WSA_WAIT_TIMEOUT)
        return 0;
    else if (wsaResult == WSA_WAIT_FAILED)
        return ResultCode.error;

    int result, errorCount;
    for (size_t i = wsaResult - WSA_WAIT_EVENT_0; i < waitHandles.length; ++i)
    {
        // prepareWaitEvent was failed
        if (!waitEvents[i].canWait())
            continue;

        WSANETWORKEVENTS ne;
        if (WSAEnumNetworkEvents(waitEvents[i].fd, waitHandles[i], &ne) != 0)
        {
            waitEvents[i].lastErrorNumber = lastSocketError();
            errorCount++;
        }
        else if (ne.lNetworkEvents != 0)
        {
            waitEvents[i].setResultEvent(ne);
            if (result < events.length)
            {
                events[result].fd = waitEvents[i].fd;
                events[result].events = ne;
                events[result].data = waitEvents[i].pollEvent.data;
            }
            result++;
        }
    }

    if (result || errorCount)
    {
        auto lock = RAIIMutex(mutex);
        if (auto data = epfd in epfdData)
        {
            foreach (ref we; waitEvents)
                data.setLastWaitEvent(we);
        }
    }

    return result;
}

/**
 * Closes an epoll instance
 * Params:
 *  epfd = epoll descriptor created by epoll_create or epoll_create1
 * Returns:
 *  0 = success
 *  -1 = error and WSAGetLastError function call will return the specific error code
 */
int epoll_close(int epfd) nothrow @trusted
{
    auto lock = RAIIMutex(mutex);

    if (auto data = epfd in epfdData)
    {
        data.cleanup();
        epfdData.remove(epfd);
        return ResultCode.ok;
    }

    lastSocketError(WSAEBADF);
    return ResultCode.error;
}

/**
 * Convert a Windows epoll events into compatible posix epoll events
 */
EPollEvent toPollEvent(ref EPollEventEx epe) nothrow pure @safe
{
    EPollEvent result;
    result.events = 0;
    result.data = epe.data;

    const lNetworkEvents = epe.events.lNetworkEvents;
    if (lNetworkEvents & FD_READ)
        result.events |= epe.events.iErrorCode[FD_READ_BIT] == 0 ? (EPOLLIN | EPOLLRDNORM) : EPOLLERR;

    if (lNetworkEvents & FD_WRITE)
        result.events |= epe.events.iErrorCode[FD_WRITE_BIT] == 0 ? (EPOLLOUT | EPOLLWRNORM) : EPOLLERR;

    if (lNetworkEvents & FD_OOB_BIT)
        result.events |= epe.events.iErrorCode[FD_OOB_BIT] == 0 ? EPOLLPRI : EPOLLERR;

    if (lNetworkEvents & FD_CLOSE)
        result.events |= epe.events.iErrorCode[FD_CLOSE_BIT] == 0 ? EPOLLHUP : EPOLLERR;

    return result;
}

/**
 * Convert a posix epoll events into compatible Windows FD_XXX network events
 */
int toWaitMask(const(uint) events) @nogc nothrow pure @safe
{
    int result = 0;

    if (events & (EPOLLIN | EPOLLRDNORM))
        result |= FD_READ;

    if (events & EPOLLRDBAND)
        result |= FD_OOB | FD_READ;

    if (events & (EPOLLOUT | EPOLLWRNORM))
        result |= FD_WRITE;

    if (events & EPOLLWRBAND)
        result |= FD_OOB | FD_WRITE;

    if (events & EPOLLRDHUP)
        result |= FD_CLOSE;

    if (events & EPOLLPRI)
        result |= FD_OOB;

    if (events & EPOLLHUP)
        result |= FD_CLOSE;

    return result;
}

private:

import core.sync.mutex : Mutex;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_object : RAIIMutex;

struct EPollSocketFD
{
    this(SocketHandle fd, EPollEvent pollEvent) nothrow @safe
    {
        this.fd = fd;
        this.pollEvent = pollEvent;
    }

    pragma(inline, true)
    bool canWait() const nothrow @safe
    {
        return waitHandle != WSAEVENT.init;
    }

    void changeEvent(EPollEvent pollEvent) nothrow @safe
    {
        cleanupWaitEvent();
        this.pollEvent = pollEvent;
    }

    void cleanupWaitEvent() nothrow @trusted
    {
        if (waitHandle == WSAEVENT.init)
        {
            WSAEventSelect(fd, WSA_INVALID_EVENT, 0);
            WSACloseEvent(waitHandle);
            waitHandle = WSAEVENT.init;
        }
        lastErrorNumber = 0;
        pollResult = WSANETWORKEVENTS.init;
    }

    void clearResultEvent() nothrow @safe
    {
        lastErrorNumber = 0;
        pollResult = WSANETWORKEVENTS.init;
    }

    int prepareWaitEvent() nothrow @trusted
    {
        lastErrorNumber = 0;
        pollResult = WSANETWORKEVENTS.init;

        if (waitHandle == WSAEVENT.init)
        {
            waitHandle = WSACreateEvent();
            if (waitHandle == WSA_INVALID_EVENT)
            {
                lastErrorNumber = lastSocketError();
                waitHandle = WSAEVENT.init;
                return ResultCode.error;
            }

            if (WSAEventSelect(fd, waitHandle, pollEvent.events) == SOCKET_ERROR)
            {
                lastErrorNumber = lastSocketError();
                WSACloseEvent(waitHandle);
                waitHandle = WSAEVENT.init;
                lastSocketError(lastErrorNumber); // Set back the original error number
                return ResultCode.error;
            }
        }

        return ResultCode.ok;
    }

    void setResultEvent(ref const(WSANETWORKEVENTS) pollResult) @nogc nothrow @safe
    {
        lastErrorNumber = 0;
        this.pollResult = pollResult;

        if (lastErrorNumber == 0 && (pollResult.lNetworkEvents & FD_READ))
            lastErrorNumber = pollResult.iErrorCode[FD_READ_BIT];

        if (lastErrorNumber == 0 && (pollResult.lNetworkEvents & FD_WRITE))
            lastErrorNumber = pollResult.iErrorCode[FD_WRITE_BIT];

        if (lastErrorNumber == 0 && (pollResult.lNetworkEvents & FD_OOB_BIT))
            lastErrorNumber = pollResult.iErrorCode[FD_OOB_BIT];

        if (lastErrorNumber == 0 && (pollResult.lNetworkEvents & FD_CLOSE))
            lastErrorNumber = pollResult.iErrorCode[FD_CLOSE_BIT];
    }

    SocketHandle fd;
    EPollEvent pollEvent; // pollEvent.events is actual FD_XXX network events
    WSANETWORKEVENTS pollResult;
    WSAEVENT waitHandle;
    int lastErrorNumber;
}

struct EPollInternalFD
{
    this(int epfd, int size, int flags) nothrow @safe
    in
    {
        assert(epfd > 0);
        assert(size > 0);
    }
    do
    {
        this.epfd = epfd;
        this.flags = flags;
        this.fdEvents.reserve(size);
    }

    int addEvent(SocketHandle fd, EPollEvent event) nothrow @safe
    {
        if (indexOfSocket(fd) >= 0)
        {
            lastSocketError(ERROR_ALREADY_EXISTS);
            return ResultCode.error;
        }

        auto epv = EPollSocketFD(fd, event);
        if (epv.prepareWaitEvent() == ResultCode.ok)
        {
            fdEvents ~= epv;
            return ResultCode.ok;
        }

        return ResultCode.error;
    }

    int changeEvent(SocketHandle fd, EPollEvent event) nothrow @safe
    {
        const i = indexOfSocket(fd);
        if (i < 0)
        {
            lastSocketError(WSAEBADF);
            return ResultCode.error;
        }

        fdEvents[i].changeEvent(event);
        return fdEvents[i].prepareWaitEvent();
    }

    void cleanup() nothrow
    {
        foreach (ref fdEvent; fdEvents)
            fdEvent.cleanupWaitEvent();
        fdEvents = [];
        epfd = flags = 0;
    }

    int deleteEvent(SocketHandle fd) nothrow @safe
    {
        const i = indexOfSocket(fd);
        if (i < 0)
        {
            lastSocketError(WSAEBADF);
            return ResultCode.error;
        }

        fdEvents[i].cleanupWaitEvent();
        fdEvents.remove(i);
        return ResultCode.ok;
    }

    int getLastErrorNumber(SocketHandle fd, ref EPollEvent event) nothrow @safe
    {
        const i = indexOfSocket(fd);
        if (i < 0)
        {
            lastSocketError(WSAEBADF);
            return ResultCode.error;
        }

        event.data.u32 = fdEvents[i].lastErrorNumber;
        return ResultCode.ok;
    }

    ptrdiff_t indexOfSocket(SocketHandle fd) const nothrow @safe
    {
        foreach (i, ref fdEvent; fdEvents)
        {
            if (fdEvent.fd == fd)
                return i;
        }
        return -1;
    }

    void prepareWaitEvent(ref EPollSocketFD[] waitEvents, ref WSAEVENT[] waitHandles) nothrow @safe
    {
        waitEvents.length = waitHandles.length = fdEvents.length;
        foreach (i, ref fdEvent; fdEvents)
        {
            const r = fdEvent.prepareWaitEvent();
            waitEvents[i] = fdEvent;
            waitHandles[i] = fdEvent.waitHandle;
            // Set on the copy instance
            if (r == ResultCode.ok)
                waitEvents[i].clearResultEvent();
        }
    }

    void setLastWaitEvent(ref EPollSocketFD we) nothrow @safe
    {
        if (!we.canWait())
            return;

        const i = indexOfSocket(we.fd);
        if (i < 0)
            return;

        fdEvents[i].lastErrorNumber = we.lastErrorNumber;
        fdEvents[i].pollResult = we.pollResult;
    }

    EPollSocketFD[] fdEvents;
    int epfd;
    int flags;
}

__gshared Mutex mutex;
__gshared Dictionary!(int, EPollInternalFD) epfdData;
__gshared int epfdNextId;

shared static this() nothrow @trusted
{
    mutex = new Mutex();
}

shared static ~this() nothrow @trusted
{
    if (mutex !is null)
    {
        mutex.destroy();
        mutex = null;
    }
}

int epollCreate(int size, int flags) nothrow @trusted
{
    auto lock = RAIIMutex(mutex);

    // maintaining error condition for compatibility
    if (size < 0)
    {
        lastSocketError(WSAEINVAL);
        return ResultCode.error;
    }

    ++epfdNextId;

    // ran out of ids! wrapped around.
    if (epfdNextId > (epfdNextId + 1))
        epfdNextId = 1;

    while (epfdNextId < (epfdNextId + 1))
    {
        if (!epfdData.containKey(epfdNextId))
            break;

        ++epfdNextId;
    }

    // two billion fds
    if (epfdNextId < 0)
    {
        lastSocketError(WSAEMFILE);
        return ResultCode.error;
    }

    epfdData[epfdNextId] = EPollInternalFD(epfdNextId, size, flags);
    return epfdNextId;
}
