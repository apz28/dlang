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

import pham.xml.xml_message;
import pham.xml.xml_object;

@safe:

template XmlExceptionConstructors()
{
@safe:

public:
    this(string message,
        string file = __FILE__, size_t line = __LINE__, Exception next = null) nothrow pure
    {
        super(message, file, line, next);
    }

    this(XmlLoc loc, string message,
        string file = __FILE__, size_t line = __LINE__, Exception next = null) nothrow pure
    {
        if (loc.isSpecified())
            message = message ~ loc.lineMessage();

        this.loc = loc;
        super(message, file, line, next);
    }

    this(Args...)(const(char)[] fmt, Args args,
        string file = __FILE__, size_t line = __LINE__, Exception next = null) @trusted
    {
        import std.format : format;

        auto message = format(fmt, args);
        super(message, file, line, next);
    }

    this(Args...)(XmlLoc loc, const(char)[] fmt, Args args,
        string file = __FILE__, size_t line = __LINE__, Exception next = null) @trusted
    {
        import std.format : format;

        auto message = format(fmt, args);
        if (loc.isSpecified())
            message = message ~ loc.lineMessage();

        this.loc = loc;
        super(message, file, line, next);
    }
}

class XmlException : Exception
{
@safe:

public:
    mixin XmlExceptionConstructors;

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
    mixin XmlExceptionConstructors;
}

class XmlInvalidOperationException : XmlException
{
@safe:

public:
    mixin XmlExceptionConstructors;
}

class XmlParserException : XmlException
{
@safe:

public:
    mixin XmlExceptionConstructors;
}
