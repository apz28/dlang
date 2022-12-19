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
         int socketCode = 0, int vendorCode = 0, Exception next = null) pure
    {
        super(message, code, state, socketCode, vendorCode, next);
    }

    this(FbIscStatues statues, Exception next = null)
    {
        string statusMessage, statusState;
        int statusCode;
        statues.buildMessage(statusMessage, statusCode, statusState);
        
        super(statusMessage, statusCode, statusState, 0, statusCode, next);
        this.statues = statues;
    }

public:
    FbIscStatues statues;
}
