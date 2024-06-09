/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2024 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.db.db_msexception;

version(Windows):

import pham.db.db_exception;
import pham.db.db_mstype : MsResultStatus;

class MsException : DbException
{
@safe:

public:
    this(uint errorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorCode, errorMessage, next, funcName, file, line);
    }

    this(uint errorCode, string errorMessage, string sqlState, uint vendorCode,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(errorCode, errorMessage, sqlState, 0, vendorCode, next, funcName, file, line);
    }

    this(MsResultStatus status,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) nothrow pure
    {
        super(status.resultCode, status.sqlErrorMessage, status.state, 0, status.sqlErrorCode, next, funcName, file, line);
        this.status = status;
    }

public:
    MsResultStatus status;
}
