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

template JSONExceptionConstructors()
{
@safe:

public:
    this(string message,
        string file = __FILE__, size_t line = __LINE__, Exception next = null) nothrow pure
    {
        super(message, file, line, next);
    }

    this(string message, size_t sourceLine, size_t sourceColumn,
        string file = __FILE__, size_t line = __LINE__, Exception next = null) nothrow pure
    {
        import std.conv : text;

        if (sourceColumn)
            super(text(message, " (", sourceLine, ":", sourceColumn, ")"), file, line, next);
        else
            super(message, file, line, next);
    }

    // For re-throw
    this(string message, Exception next,
        string file = __FILE__, size_t line = __LINE__) nothrow pure
    {
        super(message, file, line, next);
    }
}

/**
 * Exception thrown on JSON errors
 */
class JSONException : Exception
{
@safe:

public:
    mixin JSONExceptionConstructors;
}

class JSONParserException : JSONException
{
@safe:

public:
    mixin JSONExceptionConstructors;
}
