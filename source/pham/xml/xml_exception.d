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

module pham.xml.xml_exception;

import pham.xml.xml_object : XmlLoc;

@safe:

mixin template XmlExceptionConstructors(bool isBase = false)
{
    this(string message,
        Throwable next = null,
        string file = __FILE__, size_t line = __LINE__) nothrow pure @safe
    {
        static if (isBase)
            super(message, file, line, next);
        else
            super(message, next, file, line);
    }

    this(string message, XmlLoc loc,
        Throwable next = null,
        string file = __FILE__, size_t line = __LINE__) nothrow pure @safe
    {
        static if (isBase)
        {
            import std.conv : text;

            this.loc = loc;
            super(text(message, " (", loc.sourceLine, ":", loc.sourceColumn, ")"), file, line, next);
        }
        else
            super(message, loc, next, file, line);
    }

    // For re-throw
    this(string message, Throwable previous) nothrow pure @safe
    {
        static if (isBase)
            super(message, previous.file, previous.line, previous);
        else
            super(message, previous);
    }

    // For re-throw
    this(string message, XmlLoc loc, Throwable previous) nothrow pure @safe
    {
        static if (isBase)
        {
            this.loc = loc;
            super(message, previous.file, previous.line, previous);
        }
        else
            super(message, loc, previous);
    }
}

class XmlException : Exception
{
@safe:

public:
    mixin XmlExceptionConstructors!true;

    override string toString() @system
    {
        string s = super.toString();

        auto e = next;
        while (e !is null)
        {
            s ~= "\n\n" ~ e.toString();
            e = e.next;
        }

        return s;
    }

public:
    XmlLoc loc;
}

class XmlConvertException : XmlException
{
@safe:

public:
    mixin XmlExceptionConstructors!false;
}

class XmlInvalidOperationException : XmlException
{
@safe:

public:
    mixin XmlExceptionConstructors!false;
}

class XmlParserException : XmlException
{
@safe:

public:
    mixin XmlExceptionConstructors!false;
}
