/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.db_myexception;

import pham.db.db_exception;
import pham.db.db_mytype : MyErrorResult;

version(D_Buggy)
mixin template MyExceptionConstructors(bool isBase = false)
{
    this(MyErrorResult status,
        Throwable next = null) nothrow
    {
        static if (isBase)
        {
            super(status.errorCode, status.errorMessage, status.sqlState, status.socketCode, status.errorCode,
                next, status.funcName, status.file, status.line);
            this.status = status;
        }
        else
        {
            super(status, next);
        }
    }
}

class MyException : SkException
{
@safe:

public:
    version(D_Buggy)
    mixin DbExceptionConstructors!false;

    version(D_Buggy)
    mixin MyExceptionConstructors!true;

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

    this(MyErrorResult status,
        Throwable next = null) nothrow
    {
        super(status.errorCode, status.errorMessage, status.sqlState, status.socketCode, status.errorCode,
            next, status.funcName, status.file, status.line);
        this.status = status;
    }

    @property final bool isFatal() const @nogc nothrow
    {
        return vendorCode == 4_031;
    }

public:
    MyErrorResult status;
}
