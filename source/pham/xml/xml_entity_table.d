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

module pham.xml.xml_entity_table;

debug(debug_pham_xml_xml_entity_table) import std.stdio : writeln;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_object : singleton;
import pham.xml.xml_message;
import pham.xml.xml_object;
import pham.xml.xml_type;
import pham.xml.xml_util;

@safe:

class XmlEntityTable(S = string) : XmlObject!S
{
@safe:

public:
    this() nothrow pure
    {
        this.data = initDefault();
    }

    static XmlEntityTable!S defaultEntityTable() nothrow @trusted
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
    final bool find(scope const(C)[] encodedValue, ref S decodedValue) nothrow
    {
        //pragma(msg, "S=" ~ S.stringof ~ ", C=" ~ C.stringof);

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
        data = initDefault();
        return this;
    }

public:
    Dictionary!(S, S) data;

protected:
    static XmlEntityTable!S createDefaultEntityTable() nothrow pure
    {
        return new XmlEntityTable!S();
    }

    static Dictionary!(S, S) initDefault() nothrow pure
    {
        auto result = Dictionary!(S, S)(6, 6, DictionaryHashMix.murmurHash3);

        result["&amp;"] = "&";
        result["&apos;"] = "'";
        result["&gt;"] = ">";
        result["&lt;"] = "<";
        result["&quot;"] = "\"";

        debug(debug_pham_xml_xml_entity_table) if (result.maxCollision) debug writeln(__FUNCTION__, "(result.maxCollision=", result.maxCollision,
            ", result.collisionCount=", result.collisionCount, ", result.capacity=", result.capacity, ", result.length=", result.length, ")");

        return result;
    }

private:
    __gshared static XmlEntityTable!S _defaultEntityTable;
}


private:

unittest // XmlEntityTable.defaultEntityTable
{
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
