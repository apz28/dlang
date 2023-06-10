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

import pham.utl.object : singleton;
import pham.xml.message;
import pham.xml.object;
import pham.xml.type;
import pham.xml.util;

@safe:

class XmlEntityTable(S = string) : XmlObject!S
{
@safe:

public:
    this() nothrow pure
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
    final bool find(scope const(C)[] encodedValue, ref S decodedValue) const nothrow
    {
        if (auto e = encodedValue in data)
        {
            decodedValue = *e;
            return true;
        }
        else
            return false;
    }

    /** Reset the table with 5 standard reserved encoded XML characters
    */
    final typeof(this) reset() nothrow
    {
        data = null;
        initDefault();
        return this;
    }

public:
    S[S] data;

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


private:

unittest // XmlEntityTable.defaultEntityTable
{
    import pham.utl.test;
    traceUnitTest("unittest xml.entity_table.XmlEntityTable.defaultEntityTable");

    auto table = XmlEntityTable!string.defaultEntityTable();
    assert(table !is null);

    string s;

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
