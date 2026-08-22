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

module pham.db.db_fbexception;

import pham.db.db_exception;
import pham.db.db_type : int32;
import pham.db.db_fbtype : FbIscStatues;

version(D_Buggy)
mixin template FbExceptionConstructors(bool isBase = false)
{
    this(FbIscStatues status,
        Throwable next = null) nothrow
    {
        static if (isBase)
        {
            string statusMessage, statusState;
            int32 statusCode;
            status.buildMessage(statusMessage, statusCode, statusState);

            super(statusCode, statusMessage, statusState, status.socketCode, statusCode,
                next, status.funcName, status.file, status.line);
            this.status = status;
        }
        else
        {
            super(status, next);
        }
    }
}

class FbException : SkException
{
@safe:

public:
    version(D_Buggy)
    mixin DbExceptionConstructors!false;

    version(D_Buggy)
    mixin FbExceptionConstructors!true;

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

    this(FbIscStatues status,
        Throwable next = null) nothrow
    {
        string statusMessage, statusState;
        int32 statusCode;
        status.buildMessage(statusMessage, statusCode, statusState);

        super(statusCode, statusMessage, statusState, status.socketCode, statusCode,
            next, status.funcName, status.file, status.line);
        this.status = status;
    }

public:
    FbIscStatues status;
}

//import pham.utl.utl_trait : methodListOf;
//pragma(msg, "\n");
//pragma(msg, methodListOf!FbException);
