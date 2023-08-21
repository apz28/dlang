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

module pham.xml.xml_object;

import std.format : format;

import pham.xml.xml_message;
import pham.xml.xml_type;

@safe:

package(pham.xml) enum defaultXmlLevels = 400;
package(pham.xml) enum defaultXmlBufferCapacity = 1000;

struct XmlIdentifierList(S = string)
if (isXmlString!S)
{
nothrow @safe:

public:
    alias C = XmlChar!S;

public:
    S[S] items;

    /**
     * Returns true if name, n, is existed in table; otherwise false
     * Params:
     *  n = is a name to be searched for
     */
    bool exist(scope const(C)[] n) const
    {
        auto e = n in items;
        return e !is null;
    }

    /**
     * Insert name, n, into table
     * Params:
     *  n = is a name to be inserted
     * Returns:
     *  existing its name, n
     */
    S put(S n)
    in
    {
        assert(n.length != 0);
    }
    do
    {
        auto e = n in items;
        if (e is null)
        {
            items[n] = n;
            return n;
        }
        else
            return *e;
    }

    alias items this;
}

abstract class XmlObject(S)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;
}

struct XmlLoc
{
nothrow @safe:

public:
    this(size_t line, size_t column)
    {
        this.line = line;
        this.column = column;
    }

    bool isSpecified() const
    {
        return line != 0 || column != 0;
    }

    string lineMessage() const
    {
        scope (failure) assert(0, "Assume nothrow failed");
        
        return format(XmlMessage.atLineInfo, sourceLine, sourceColumn);
    }

    @property size_t sourceColumn() const
    {
        return column + 1;
    }

    @property size_t sourceLine() const
    {
        return line + 1;
    }

public:
    // Zero based index values
    size_t line;
    size_t column;
}
