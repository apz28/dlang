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

module pham.xml.entity_table;

import pham.utl.utlobject;
import pham.xml.type;
import pham.xml.message;
import pham.xml.util;
import pham.xml.xmlobject;

@safe:

class XmlEntityTable(S = string) : XmlObject!S
{
public:
    this() pure
    {
        initDefault();
    }

    static const(XmlEntityTable!S) defaultEntityTable() nothrow @trusted
    {
        return singleton!(XmlEntityTable!S)(_defaultEntityTable, &createDefaultEntityTable);
    }

    /** Find an encodedValue and set the decodedValue if it finds a match
        Params:
            encodedValue = a string type XML encoded value to search for
            decodedValue = a corresponding XML decoded value if found
        Returns:
            true if encodedValue found in the table
            false otherwise
    */
    final bool find(scope const(C)[] encodedValue, ref const(C)[] decodedValue) const nothrow
    {
        const const(C)[]* r = encodedValue in data;

        if (r is null)
            return false;
        else
        {
            decodedValue = *r;
            return true;
        }
    }

    /** Reset the table with 5 standard reserved encoded XML characters
    */
    final void reset() nothrow
    {
        data = null;
        initDefault();
    }

    alias data this;

public:
    const(C)[][const(C)[]] data;

protected:
    static XmlEntityTable!S createDefaultEntityTable() nothrow pure
    {
        return new XmlEntityTable!S();
    }

    final void initDefault() nothrow pure
    {
        data["&amp;"] = "&";
        data["&apos;"] = "'";
        data["&gt;"] = ">";
        data["&lt;"] = "<";
        data["&quot;"] = "\"";

        (() @trusted => data.rehash())();
    }

private:
    __gshared static XmlEntityTable!S _defaultEntityTable;
}

unittest // XmlEntityTable.defaultEntityTable
{
    outputXmlTraceProgress("unittest xml.entity_table.XmlEntityTable.defaultEntityTable");

    auto table = XmlEntityTable!string.defaultEntityTable();
    assert(table !is null);

    const(XmlChar!string)[] s;

    assert(table.find("&amp;", s));
    assert(s == "&");

    assert(table.find("&apos;", s));
    assert(s == "'");

    assert(table.find("&gt;", s));
    assert(s == ">");

    assert(table.find("&lt;", s));
    assert(s == "<");

    assert(table.find("&quot;", s));
    assert(s == "\"");

    assert(table.find("", s) == false);
    assert(table.find("&;", s) == false);
    assert(table.find("?", s) == false);
}
