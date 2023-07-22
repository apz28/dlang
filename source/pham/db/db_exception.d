/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2017 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.db.exception;

version (TraceFunction) import pham.utl.test;
import pham.db.message;

class DbException : Exception
{
@safe:

public:
    this(string message, int code, string sqlState,
        int socketCode = 0, int vendorCode = 0,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) pure
    {
        version (TraceFunction) debug traceFunction();

        if (code)
            message ~= "\n" ~ DbMessage.eErrorCode.fmtMessage(code);

        if (sqlState.length)
            message ~= "\n" ~ DbMessage.eErrorSqlState.fmtMessage(sqlState);

        super(message, file, line, next);
        this.funcName = funcName;
        this.sqlState = sqlState;
        this.code = code;
        this.socketCode = socketCode;
        this.vendorCode = vendorCode;
    }

    override string toString() @trusted
    {
        version (TraceFunction) traceFunction();

        auto result = super.toString();

        auto e = next;
        while (e !is null)
        {
            result ~= "\n\n" ~ e.toString();
            e = e.next;
        }

        return result;
    }

public:
    string funcName;
    string sqlState;
    int code;
    int socketCode;
    int vendorCode;
}

class SkException : DbException
{
@safe:

public:
    this(string message, int code, string sqlState,
        int socketCode = 0, int vendorCode = 0,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) pure
    {
        super(message, code, sqlState, socketCode, vendorCode, next, funcName, file, line);
    }
}
