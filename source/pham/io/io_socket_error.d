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
import pham.utl.utl_result : genericErrorMessage, getSystemErrorMessage, ResultStatus;

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
        import core.sys.windows.winsock2;

        return WSAGetLastError();
    }
    else version(Posix)
    {
        import core.stdc.errno;

        return errno;
    }
    else
    {
        static assert(0, "Unsupported system for " ~ __FUNCTION__);
    }
}

ResultStatus lastSocketError(string apiName, string defaultMessage = null,
    string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
{
    const code = lastSocketError();
    const message = code != 0 ? getSystemErrorMessage(code) : defaultMessage;
    return ResultStatus.error(code, message.length != 0 ? message : genericErrorMessage(apiName, code), funcName, file, line);
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
        pragma(msg, "Unsupported system for " ~ __MODULE__);
}
