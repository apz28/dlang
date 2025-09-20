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

module pham.io.io_socket_error;

import pham.utl.utl_array_dictionary;
import pham.utl.utl_result : ResultStatus,
    genericErrorMessage, getSystemErrorMessage;

@safe:

string getSocketAPIName(scope const(char)[] mapFunctionName) nothrow pure
{
    if (auto e = mapFunctionName in mapSocketAPINames)
        return *e;

    assert(0, "Invalid mapFunctionName: " ~ mapFunctionName);
}

pragma(inline, true)
int lastSocketError() @nogc nothrow @trusted
{
    version(Windows)
    {
        import core.sys.windows.winsock2 : WSAGetLastError;

        return WSAGetLastError();
    }
    else version(Posix)
    {
        import core.stdc.errno : errno;

        return errno;
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
        return 0;
    }
}

ResultStatus lastSocketError(string apiName, string defaultMessage = null,
    string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
{
    const code = lastSocketError();
    const message = code != 0 ? getSystemErrorMessage(code) : defaultMessage;
    return ResultStatus.error(code, message.length != 0 ? message : genericErrorMessage(apiName, code), funcName, file, line);
}

bool needResetSocket(int errorCode) @nogc nothrow pure @safe
{
    version(Windows)
    {
        //import core.sys.windows.winerror;
        import core.sys.windows.winsock2;

        // https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-recv
        // https://learn.microsoft.com/en-us/windows/win32/api/winsock2/nf-winsock2-send
        switch (errorCode)
        {
            case WSAENETDOWN:
            case WSAENETRESET:
            case WSAENOTSOCK:
            case WSAESHUTDOWN:
            case WSAECONNABORTED:
            case WSAECONNRESET:
            // Addition from send
            case WSAENOTCONN:
            case WSAEHOSTUNREACH:
                return true;
            default:
                return false;
        }
    }
    else version(Posix)
    {
        import core.stdc.errno;
        //import core.sys.posix.sys.socket;

        // https://linux.die.net/man/2/recv
        // https://linux.die.net/man/2/send
        switch (errorCode)
        {
            case EBADF:
            case ECONNREFUSED:
            case ENOTCONN:
            case ENOTSOCK:
            // Addition from send
            case ECONNRESET:
            case EDESTADDRREQ:
            case EPIPE:
                return true;
            default:
                return false;
        }
    }
    else
    {
        pragma(msg, __FUNCTION__ ~ "() not supported");
        return false;
    }
}

static immutable Dictionary!(string, string) mapSocketAPINames;


private:

import core.attribute : standalone;

@standalone
shared static this() nothrow @trusted
{
    version(Posix)
    {
        auto names = Dictionary!(string, string)(30, 25);

        names["acceptSocket"] = "accept";
        names["bindSocket"] = "bind";
        names["closeSocket"] = "closesocket";
        names["connectSocket"] = "connect";
        names["createSocket"] = "socket";
        names["getAvailableBytesSocket"] = "ioctlsocket";
        names["getComputerNameOS"] = "gethostname";
        names["getOptionSocket"] = "getsockopt";
        names["getReadTimeoutSocket"] = "getsockopt";
        names["getWriteTimeoutSocket"] = "getsockopt";
        names["interfaceNameToIndex"] = "if_nametoindex";
        names["lastSocketErrorOf"] = "getsockopt";
        names["listenSocket"] = "listen";
        names["pollSocket"] = "poll";
        names["receiveSocket"] = "recv";
        names["selectSocket"] = "select";
        names["sendSocket"] = "send";
        names["setBlockingSocket"] = "ioctlsocket";
        names["setOptionSocket"] = "setsockopt";
        names["setLingerSocket"] = "setsockopt";
        names["setReadTimeoutSocket"] = "setsockopt";
        names["setWriteTimeoutSocket"] = "setsockopt";
        names["shutdownSocket"] = "shutdown";
        names["waitForConnectSocket"] = "select";

        mapSocketAPINames = cast(immutable)names;
    }
    else version(Windows)
    {
        auto names = Dictionary!(string, string)(30, 25);

        names["acceptSocket"] = "accept";
        names["bindSocket"] = "bind";
        names["closeSocket"] = "close";
        names["connectSocket"] = "connect";
        names["createSocket"] = "socket";
        names["getAvailableBytesSocket"] = "ioctl";
        names["getBlockingSocket"] = "?";
        names["getComputerNameOS"] = "GetComputerNameA";
        names["getOptionSocket"] = "getsockopt";
        names["getReadTimeoutSocket"] = "getsockopt";
        names["getWriteTimeoutSocket"] = "getsockopt";
        names["interfaceNameToIndex"] = "if_nametoindex";
        names["lastSocketErrorOf"] = "getsockopt";
        names["listenSocket"] = "listen";
        names["pollSocket"] = "WSAPoll";
        names["receiveSocket"] = "recv";
        names["selectSocket"] = "select";
        names["sendSocket"] = "send";
        names["setBlockingSocket"] = "fcntl";
        names["setOptionSocket"] = "setsockopt";
        names["setLingerSocket"] = "setsockopt";
        names["setReadTimeoutSocket"] = "setsockopt";
        names["setWriteTimeoutSocket"] = "setsockopt";
        names["shutdownSocket"] = "shutdown";
        names["waitForConnectSocket"] = "select";

        mapSocketAPINames = cast(immutable)names;
    }
    else
    {
        pragma(msg, __MODULE__ ~ " not supported");
    }
}
