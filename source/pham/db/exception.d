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

module pham.db.exception;

import std.format : format;

import pham.db.message;

class DbException : Exception
{
@safe:

public:
    this(string message, int code, int socketCode, int vendorCode, Exception next = null)
    {
        if (code)
            message ~= "\n" ~ format(DbMessage.eErrorCode, code);

        super(message, next);
        this.code = code;
        this.socketCode = socketCode;
        this.vendorCode = vendorCode;
    }

    override string toString() @trusted
    {
        auto result = super.toString();

        auto e = next;
        while (e !is null)
        {
            result ~= "\n\n" ~ e.toString();
            e = e.next;
        }

        return result;
    }

public:
    int code;
    int socketCode;
    int vendorCode;
}

class SkException : DbException
{
@safe:

public:
    this(string message, int code, int socketCode, int vendorCode, Exception next = null)
    {
        super(message, code, socketCode, vendorCode, next);
    }
}
