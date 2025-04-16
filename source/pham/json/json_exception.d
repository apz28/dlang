/*
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */
module pham.json.json_exception;

import std.conv : text;

/**
 * Exception thrown on JSON errors
 */
class JSONException : Exception
{
public:
    this(string msg, string file = __FILE__, size_t line = __LINE__, Exception next = null) nothrow pure @safe
    {
        super(msg, file, line, next);
    }

    this(string msg, size_t line, uint column, string file = __FILE__, Exception next = null) nothrow pure @safe
    {
        if (column)
            super(text(msg, " (", line, ":", column, ")"), file, 0, next);
        else
            super(msg, file, line, next);
    }
}
