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

module pham.db.db_exception;

import pham.db.db_message;

enum esocketReadTimeout = 10060;

version(D_Buggy)
mixin template DbExceptionConstructors(bool isBase = false)
{
    this(uint errorCode, string errorMessage,
        Throwable next = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow @safe
    {
        static if (isBase)
        {
            if (errorCode)
                addMessageLine(errorMessage, DbMessage.eErrorCode.fmtMessage(errorCode));

            super(errorMessage, file, line, next);
            this.errorCode = errorCode;
            this.funcName = funcName;
            this.sqlState = null;
            this.socketCode = 0;
            this.vendorCode = 0;
        }
        else
        {
            super(errorCode, errorMessage, next, funcName, file, line);
        }
    }

    this(uint errorCode, string errorMessage, string sqlState, uint socketCode, uint vendorCode,
        Throwable next = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow @safe
    {
        static if (isBase)
        {
            if (errorCode)
                addMessageLine(errorMessage, DbMessage.eErrorCode.fmtMessage(errorCode));

            if (sqlState.length)
                addMessageLine(errorMessage, DbMessage.eErrorSqlState.fmtMessage(sqlState));

            super(errorMessage, file, line, next);
            this.errorCode = errorCode;
            this.funcName = funcName;
            this.sqlState = sqlState;
            this.socketCode = socketCode;
            this.vendorCode = vendorCode;
        }
        else
        {
            super(errorCode, errorMessage, sqlState, socketCode, vendorCode, next, funcName, file, line);
        }
    }
}

class DbException : Exception
{
@safe:

public:
    version(D_Buggy)
    mixin DbExceptionConstructors!true;

    this(uint errorCode, string errorMessage,
        Throwable next = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow @safe
    {
        if (errorCode)
            addMessageLine(errorMessage, DbMessage.eErrorCode.fmtMessage(errorCode));

        super(errorMessage, file, line, next);
        this.errorCode = errorCode;
        this.funcName = funcName;
        this.sqlState = null;
        this.socketCode = 0;
        this.vendorCode = 0;
    }

    this(uint errorCode, string errorMessage, string sqlState, uint socketCode, uint vendorCode,
        Throwable next = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow @safe
    {
        if (errorCode)
            addMessageLine(errorMessage, DbMessage.eErrorCode.fmtMessage(errorCode));

        if (sqlState.length)
            addMessageLine(errorMessage, DbMessage.eErrorSqlState.fmtMessage(sqlState));

        super(errorMessage, file, line, next);
        this.errorCode = errorCode;
        this.funcName = funcName;
        this.sqlState = sqlState;
        this.socketCode = socketCode;
        this.vendorCode = vendorCode;
    }

    override string toString() @trusted
    {
        auto result = super.toString();

        auto e = next;
        while (e !is null)
        {
            addMessageLine(result, "");
            addMessageLine(result, e.toString());
            e = e.next;
        }

        return result;
    }

public:
    string funcName;
    string sqlState;
    uint errorCode;
    uint socketCode;
    uint vendorCode;
}

class SkException : DbException
{
@safe:

public:
    version(D_Buggy)
    mixin DbExceptionConstructors!false;

    this(uint errorCode, string errorMessage,
        Throwable next = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow @safe
    {
        super(errorCode, errorMessage, next, funcName, file, line);
    }

    this(uint errorCode, string errorMessage, string sqlState, uint socketCode, uint vendorCode,
        Throwable next = null,
        string funcName = __FUNCTION__, string file = __FILE__, size_t line = __LINE__) nothrow @safe
    {
        super(errorCode, errorMessage, sqlState, socketCode, vendorCode, next, funcName, file, line);
    }
}

//import pham.utl.utl_trait : methodListOf;
//pragma(msg, "\n");
//pragma(msg, methodListOf!DbException);
//pragma(msg, "\n");
//pragma(msg, methodListOf!SkException);
