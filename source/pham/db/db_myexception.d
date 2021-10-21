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

class MyException : SkException
{
@safe:

public:
    this(string message, int code, int socketCode, int vendorCode, Exception next = null)
    {
        super(message, code, socketCode, vendorCode, next);
    }

public:
}
