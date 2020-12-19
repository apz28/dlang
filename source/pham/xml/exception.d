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

module pham.xml.exception;

import pham.xml.message;
import pham.xml.xmlobject;

@safe:

template XmlExceptionConstructors()
{
    this(string message, Exception next)
    {
        super(message, next);
    }

    this(XmlLoc loc, string message, Exception next)
    {
        if (loc.isSpecified())
            message = message ~ loc.lineMessage();

        loc = loc;
        super(message, next);
    }

    this(Args...)(const(char)[] fmt, Args args) @trusted
    {
        import std.format : format;

        string msg = format(fmt, args);
        super(msg);
    }

    this(Args...)(XmlLoc loc, const(char)[] fmt, Args args) @trusted
    {
        import std.format : format;

        string msg = format(fmt, args);

        if (loc.isSpecified())
            msg = msg ~ loc.lineMessage();

        loc = loc;
        super(msg);
    }
}

class XmlException : Exception
{
public:
    XmlLoc loc;

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
}

class XmlConvertException : XmlException
{
public:
    mixin XmlExceptionConstructors;
}

class XmlInvalidOperationException : XmlException
{
public:
    mixin XmlExceptionConstructors;
}

class XmlParserException : XmlException
{
public:
    mixin XmlExceptionConstructors;
}
