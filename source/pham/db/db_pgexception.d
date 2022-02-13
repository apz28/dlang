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

module pham.db.pgexception;

import pham.db.exception;
import pham.db.message : DbErrorCode;
import pham.db.pgtype : PgGenericResponse;

class PgException : SkException
{
@safe:

public:
    this(string message, int code, string sqlState,
        int socketCode = 0, int vendorCode = 0, Exception next = null) pure
    {
        super(message, code, sqlState, socketCode, vendorCode, next);
    }

    this(PgGenericResponse statues, Exception next = null)
    {
        auto statusMessage = statues.errorString();
        auto statusSqlState = statues.sqlState();
        auto statusCode = statues.errorCode();
        super(statusMessage, statusCode, statusSqlState, 0, statusCode, next);
        this.statues = statues;
    }

public:
    PgGenericResponse statues;
}
