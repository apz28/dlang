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

module pham.db.myexception;

import pham.db.exception;
import pham.db.mytype : MyErrorResult;

class MyException : SkException
{
@safe:

public:
    this(string message, int code, string sqlState,
        int socketCode = 0, int vendorCode = 0,
        string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure
    {
        super(message, code, sqlState, socketCode, vendorCode, file, line, next);
    }

    this(MyErrorResult errorResult,
        string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure
    {
        super(errorResult.message, errorResult.code, errorResult.sqlState, 0, errorResult.code, file, line, next);
        this.errorResult = errorResult;
    }

    @property final bool isFatal() const @nogc nothrow pure
    {
        return vendorCode == 4_031;
    }

public:
    MyErrorResult errorResult;
}
