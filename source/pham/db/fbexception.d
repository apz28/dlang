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
import pham.db.fbtype;

class FbException : SkException
{
@safe:

public:
    this(string message, int code, int socketCode, int vendorCode, Exception next = null) pure
    {
        super(message, code, socketCode, vendorCode, next);
    }

    this(FbIscStatues statues, Exception next = null)
    {
        string statusMsg;
        int statusCode;
        statues.buildMessage(statusMsg, statusCode);
        super(statusMsg, statusCode, 0, statusCode, next);
        this.statues = statues;
    }

public:
    FbIscStatues statues;
}
