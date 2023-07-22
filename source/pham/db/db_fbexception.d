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

module pham.db.fbexception;

import pham.db.exception;
import pham.db.fbtype : FbIscStatues;

class FbException : SkException
{
@safe:

public:
    this(string message, int code, string state,
        int socketCode = 0, int vendorCode = 0,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__) pure
    {
        super(message, code, state, socketCode, vendorCode, next, funcName, file, line);
    }

    this(FbIscStatues statues,
        Throwable next = null, string funcName = __FUNCTION__, string file = __FILE__, uint line = __LINE__)
    {
        string statusMessage, statusState;
        int statusCode;
        statues.buildMessage(statusMessage, statusCode, statusState);

        super(statusMessage, statusCode, statusState, 0, statusCode, next, funcName, file, line);
        this.statues = statues;
    }

public:
    FbIscStatues statues;
}
