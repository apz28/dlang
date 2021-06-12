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
import pham.db.message;
import pham.db.pgtype;

class PgException : SkException
{
@safe:

public:
    this(string message, int code, int socketCode, int vendorCode, Exception next = null)
    {
        super(message, code, socketCode, vendorCode, next);
    }

    //TODO code & vendorCode?
    this(PgGenericResponse statues, Exception next = null)
    {
        super(statues.errorString(), DbErrorCode.read, 0, statues.errorCode(), next);
        this.statues = statues;
    }

public:
    PgGenericResponse statues;
}
