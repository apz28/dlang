/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2020 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.db_pgexception;

import pham.db.db_exception;
import pham.db.db_pgtype : PgGenericResponse;

version(D_Buggy)
mixin template PgExceptionConstructors(bool isBase = false)
{
    this(PgGenericResponse status,
        Throwable next = null) nothrow
    {
        static if (isBase)
        {
            auto statusErrorCode = status.errorCode();
            super(statusErrorCode, status.errorString(), status.sqlState(), status.socketCode, statusErrorCode,
                next, status.funcName, status.file, status.line);
            this.status = status;
        }
        else
        {
            super(status, next);
        }
    }
}

class PgException : SkException
{
@safe:

public:
    version(D_Buggy)
    mixin DbExceptionConstructors!false;

    version(D_Buggy)
    mixin PgExceptionConstructors!true;

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

    this(PgGenericResponse status,
        Throwable next = null) nothrow
    {
        auto statusErrorCode = status.errorCode();
        super(statusErrorCode, status.errorString(), status.sqlState(), status.socketCode, statusErrorCode,
            next, status.funcName, status.file, status.line);
        this.status = status;
    }

public:
    PgGenericResponse status;
}
