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

module pham.xml.xml_string;

import std.typecons : Flag, No, Yes;

import pham.xml.xml_buffer;
import pham.xml.xml_entity_table;
import pham.xml.xml_message;
import pham.xml.xml_type;
import pham.xml.xml_util;

@safe:

struct XmlString(S = string)
if (isXmlString!S)
{
@safe:

public:
    alias C = XmlChar!S;

public:
    this(S str) nothrow
    {
        this(str, XmlEncodeMode.check);
    }

    this(S str, XmlEncodeMode mode) nothrow
    {
        this.data = str;
        this.mode = mode;
    }

    ref typeof(this) opAssign(S value) nothrow
    {
        this.data = value;
        if (mode != XmlEncodeMode.none)
            mode = XmlEncodeMode.check;

        return this;
    }

    version(none)
    S opCall()
    {
        return data;
    }

    S decodedText(XmlDecodeMode DecodeMode = XmlDecodeMode.strict)(XmlBuffer!(S, No.CheckEncoded) buffer, in XmlEntityTable!S entityTable)
    in
    {
        assert(buffer !is null);
        assert(entityTable !is null);
        assert(needDecode());
    }
    do
    {
        return buffer.decode!DecodeMode(data, entityTable);
    }

    S encodedText(XmlBuffer!(S, No.CheckEncoded) buffer) nothrow
    in
    {
        assert(buffer !is null);
        assert(needEncode());
    }
    do
    {
        return buffer.encode(data);
    }

    bool needDecode() const nothrow
    {
        return (data.length != 0) &&
            (mode == XmlEncodeMode.encoded || mode == XmlEncodeMode.check);
    }

    bool needEncode() const nothrow
    {
        return (data.length != 0) &&
            (mode == XmlEncodeMode.decoded || mode == XmlEncodeMode.check);
    }

    @property size_t length() const nothrow
    {
        return data.length;
    }

    S rawValue() const nothrow
    {
        return data;
    }

    @property S value() nothrow
    {
        if (needDecode())
        {
            auto buffer = new XmlBuffer!(S, No.CheckEncoded)(data.length);
            data = buffer.decode!(XmlDecodeMode.loose)(data);
            mode = buffer.decodeOrEncodeResultMode;
        }

        return data;
    }

    @property S value(S newText) nothrow
    {
        data = newText;
        if (mode != XmlEncodeMode.none)
            mode = XmlEncodeMode.check;

        return data;
    }

private:
    S data;
    XmlEncodeMode mode;
}

version(none)
pragma (inline, true)
XmlString!S toXmlString(S, Flag!"CheckEncoded" CheckEncoded)(XmlBuffer!(S, CheckEncoded) buffer)
{
    auto m = buffer.decodeOrEncodeResultMode;
    return XmlString!S(buffer.value(), m);
}

pragma (inline, true)
XmlString!S toXmlStringAndClear(S, Flag!"CheckEncoded" CheckEncoded)(XmlBuffer!(S, CheckEncoded) buffer)
{
    auto m = buffer.decodeOrEncodeResultMode;
    return XmlString!S(buffer.valueAndClear(), m);
}
