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

import pham.utl.utl_result : genericErrorMessage, getSystemErrorMessage, ResultStatus;

@safe:

int lastSocketError() @nogc nothrow @trusted
{
    version (Windows)
    {
        import core.sys.windows.winsock2;

        return WSAGetLastError();
    }
    else version (Posix)
    {
        import core.stdc.errno;

        return errno;
    }
    else
    {
        pragma(msg, "No socket error code for this platform.");
        return 0;
    }
}

ResultStatus lastSocketError(string apiName,
    string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow
{
    auto code = lastSocketError();
    auto message = getSystemErrorMessage(code);
    return ResultStatus.error(code, message.length != 0 ? message : genericErrorMessage(apiName, code), funcName, file, line);
}
