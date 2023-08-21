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

class MyException : SkException
{
@safe:

public:
    this(uint errorCode, string errorMessage,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) pure
    {
        super(errorCode, errorMessage, next, funcName, file, line);
    }

    this(uint errorCode, string errorMessage, string sqlState, uint socketCode, uint vendorCode,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) pure
    {
        super(errorCode, errorMessage, sqlState, socketCode, vendorCode, next, funcName, file, line);
    }

    this(MyErrorResult errorResult,
        Throwable next = null) pure
    {
        super(errorResult.errorCode, errorResult.errorMessage, errorResult.sqlState, 0, errorResult.errorCode,
            next, errorResult.funcName, errorResult.file, errorResult.line);
    }

    @property final bool isFatal() const @nogc nothrow pure
    {
        return vendorCode == 4_031;
    }
}
