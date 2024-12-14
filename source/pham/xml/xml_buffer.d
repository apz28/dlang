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

module pham.xml.xml_buffer;

import std.typecons : Flag, No, Yes;

debug(debug_pham_xml_xml_buffer) import std.stdio : writeln;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_dlink_list;
import pham.xml.xml_entity_table;
import pham.xml.xml_exception;
import pham.xml.xml_message;
import pham.xml.xml_object;
import pham.xml.xml_type;
import pham.xml.xml_util;

@safe:

/**
 * Mode to use for decoding.
 * $(XmlDecodeMode.loose) Decode but ignore on error (if not able to substitute the entity text, leave it as is)
 * $(XmlDecodeMode.strict) Decode and throw exception on error (if not able to substitute the entity text)
 */
enum XmlDecodeMode : ubyte
{
    loose,
    strict,
}

/**
 * A state if a string if it has an reserved xml character
 * $(XmlEncodeMode.check) A text need to be checked for reserved char
 * $(XmlEncodeMode.checked) A text is already checked and it does not have reserved character
 * $(XmlEncodeMode.decoded) A text has reserved character in decoded form
 * $(XmlEncodeMode.encoded) A text has reserved char in encoded form
 * $(XmlEncodeMode.none) A text should be left as-is and no need to do encode or decode check
 */
enum XmlEncodeMode : ubyte
{
    check,
    checked,
    decoded,
    encoded,
    none,
}

class XmlBuffer(S = string, Flag!"CheckEncoded" CheckEncoded = No.CheckEncoded) : XmlObject!S
{
@safe:

public:
    this(size_t capacity = defaultXmlBufferCapacity) nothrow
    {
        if (capacity != 0)
            _buffer.reserve(capacity);
    }

    final typeof(this) clear() nothrow
    {
        _buffer.clear();
        _decodeOrEncodeResultMode = XmlEncodeMode.checked;
        return this;
    }

    /** Decode a string. s, by unescaping all predefined XML entities.
        This function decode the entities "&amp;amp;", "&amp;quot;", "&amp;apos;",
        "&amp;lt;" and "&amp;gt", as well as decimal and hexadecimal entities
        such as &amp;#x20AC;

        Standards:
            $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)

        Params:
            s = The string to be decoded

        Throws:
            XMLExceptionConvert if decode fails

        Returns:
            The XML decoded string

        Example:
            writeln(decode("a &gt; b")); // writes "a > b"
    */
    final S decode(XmlDecodeMode DecodeMode = XmlDecodeMode.strict)(S s)
    {
        return decode!DecodeMode(s, XmlEntityTable!S.defaultEntityTable());
    }

    /** Decode a string, s, by unescaping all passed in entities in entityTable.
        This function decode the entities "&amp;amp;", "&amp;quot;", "&amp;apos;",
        "&amp;lt;" and "&amp;gt", as well as decimal and hexadecimal entities
        such as &amp;#x20AC;

        Params:
            s = The string to be decoded

        Throws:
            XMLExceptionConvert if decode fails

        Returns:
            The XML decoded string

        Example:
            writeln(decode("a &gt; b")); // writes "a > b"
    */
    final S decode(XmlDecodeMode DecodeMode = XmlDecodeMode.strict)(S s, in XmlEntityTable!S entityTable)
    {
        import std.string : startsWith;

        debug(debug_pham_xml_xml_buffer) debug writeln(__FUNCTION__, "(s=", s, ")");

        assert(entityTable !is null);

        S refChars;
        size_t i, lastI, mark;
        for (; i < s.length;)
        {
            if (s[i] != '&')
            {
                ++i;
                continue;
            }

            // Copy previous non-replace string
            if (lastI < i)
                put(s[lastI..i]);

            refChars = null;
            mark = 0;
            for (size_t j = i + 1; j < s.length && mark == 0; ++j)
            {
                switch (s[j])
                {
                    case ';':
                        refChars = s[i..j + 1];
                        mark = 1;

                        debug(debug_pham_xml_xml_buffer) debug writeln("\t", "refChars=", refChars, ", i=", i, ", j=", j);

                        break;
                    case '&':
                        refChars = s[i..j];
                        mark = 2;

                        debug(debug_pham_xml_xml_buffer) debug writeln("\t", "refChars=", refChars, ", i=", i, ", j=", j);

                        break;
                    default:
                        break;
                }
            }

            if (mark != 1 || refChars.length <= 2)
            {
                static if (DecodeMode == XmlDecodeMode.strict)
                {
                    auto msg = XmlMessage.eUnescapeAndChar ~ " " ~ toUTF!(S, string)(leftString!S(refChars, 20u).idup);
                    throw new XmlConvertException(XmlLoc(0, i), msg);
                }
                else
                {
                    if (mark == 0)
                    {
                        lastI = i;
                        break;
                    }
                    else
                    {
                        put(refChars);
                        i += refChars.length;
                    }
                }
            }
            else
            {
                debug(debug_pham_xml_xml_buffer) debug writeln("\t", "refChars=", refChars);

                if (refChars[1] == '#')
                {
                    dchar c;
                    if (!convertToChar!S(refChars[2..$ - 1], c))
                    {
                        static if (DecodeMode == XmlDecodeMode.strict)
                        {
                            auto msg = XmlMessage.eUnescapeAndChar ~ " " ~ toUTF!(S, string)(leftString!S(refChars, 20u).idup);
                            throw new XmlConvertException(XmlLoc(0, i), msg);
                        }
                        else
                        {
                            put(refChars);
                        }
                    }
                    else
                        put(c);
                }
                else
                {
                    S r;
                    if (entityTable.find(refChars, r))
                        put(r);
                    else
                    {
                        static if (DecodeMode == XmlDecodeMode.strict)
                        {
                            auto msg = XmlMessage.eUnescapeAndChar ~ " " ~ toUTF!(S, string)(leftString!S(refChars, 20u).idup);
                            throw new XmlConvertException(XmlLoc(0, i), msg);
                        }
                        else
                        {
                            put(refChars);
                        }
                    }
                }

                i += refChars.length;
            }

            debug(debug_pham_xml_xml_buffer) debug writeln("\t", "refChars=", refChars, ", i=", i);

            lastI = i;
        }

        if (length == 0)
        {
            _decodeOrEncodeResultMode = XmlEncodeMode.checked;
            return s;
        }

        put(s[lastI..$]);
        _decodeOrEncodeResultMode = XmlEncodeMode.decoded;

        return value();
    }

    /**
     * Truncates this buffer, count of elements and returns itself.
     * If count is greater then the length, it will clear the buffer
     * Params:
     *  count = how many elements to be truncated from the righ
     * Returns:
     *  The itself
     */
    final typeof(this) dropBack(size_t count) nothrow
    {
        auto len = length;
        if (len <= count)
            return clear();

        scope (failure) assert(0, "Assume nothrow failed");

        _buffer.shrinkTo(len - count);
        return this;
    }

    /**
     * Encodes a string by replacing all characters which need to be escaped with
     * appropriate predefined XML entities.
     * encode() escapes certain characters (ampersand, quote, apostrophe, less-than
     * and greater-than)
     * If the string is not modified, the original will be returned.
     * Standards:
     *  $(LINK2 http://www.w3.org/TR/1998/REC-xml-19980210, XML 1.0)
     * Params:
     *  s = The string to be encoded
     * Returns:
     *  The xml encoded string
     * Example:
     *  writeln(encode("a > b")); // writes "a &gt; b"
     */
    final S encode(S s) nothrow
    {
        debug(debug_pham_xml_xml_buffer) { debug writeln(__FUNCTION__, "(s=", s, ", value=", value(), ")");
            scope (exit) debug writeln("\t", "value=", value()); }

        S r;
        size_t lastI;
        foreach (i, c; s)
        {
            switch (c)
            {
                case '&':
                    r = "&amp;";
                    break;
                case '"':
                    r = "&quot;";
                    break;
                case '\'':
                    r = "&apos;";
                    break;
                case '<':
                    r = "&lt;";
                    break;
                case '>':
                    r = "&gt;";
                    break;
                default:
                    continue;
            }

            // Copy previous non-replace string
            if (i > lastI)
                put(s[lastI..i]);

            // Replace with r
            if (r.length != 0)
            {
                put(r);
                r = null;
            }

            lastI = i + 1;
        }

        if (length == 0)
        {
            _decodeOrEncodeResultMode = XmlEncodeMode.checked;
            return s;
        }

        put(s[lastI..$]);
        _decodeOrEncodeResultMode = XmlEncodeMode.encoded;

        return value();
    }

    /**
     * Put a character, c, to the end of buffer
     * Params:
     *  c = character to be appended at the end
     */
    pragma(inline, true)
    final void put(C c) nothrow
    {
        reserve(1);
        _buffer.put(c);

        static if (CheckEncoded)
        if (c == '&')
            _decodeOrEncodeResultMode = XmlEncodeMode.encoded;
    }

    /**
     * Put a character, c, to the end of buffer. If c is not the same type as C,
     * it will convert c to arrar of C type and append them to the end
     * Params:
     *  c = character to be appended at the end
     */
    static if (!is(C == dchar))
    final void put(dchar c) nothrow
    {
        import std.encoding : encode;

        C[6] b;
        size_t n = encode(c, b);
        reserve(n);
        _buffer.put(b[0..n]);

        static if (CheckEncoded)
        if (c == '&')
            _decodeOrEncodeResultMode = XmlEncodeMode.encoded;
    }

    /**
     * Put an array of characters, s, to the end of buffer
     * Params:
     *  s = array of characters to be appended at the end
     */
    final void put(scope const(C)[] s) nothrow
    {
        reserve(s.length);
        _buffer.put(s);

        static if (CheckEncoded)
        if (_decodeOrEncodeResultMode != XmlEncodeMode.encoded)
        {
            foreach (c; s)
            {
                if (c == '&')
                {
                    _decodeOrEncodeResultMode = XmlEncodeMode.encoded;
                    break;
                }
            }
        }
    }

    final bool rightEqual(scope const(C)[] subString) const nothrow
    {
        return equalRight!S(_buffer.data, subString);
    }

    final S rightString(size_t count) const nothrow
    {
        auto len = length;
        if (count >= len)
            return value();
        else
            return _buffer.data[len - count..len].idup;
    }

    final S value() const nothrow
    {
        return _buffer.data.idup;
    }

    final S valueAndClear() nothrow
    {
        auto result = _buffer.data.idup;
        clear();
        return result;
    }

    @property final size_t capacity() const nothrow
    {
        return _buffer.capacity;
    }

    @property final typeof(this) capacity(size_t newCapacity) nothrow
    {
        if (newCapacity > _buffer.capacity)
            _buffer.reserve(newCapacity);
        return this;
    }

    @property final XmlEncodeMode decodeOrEncodeResultMode() const nothrow
    {
        return _decodeOrEncodeResultMode;
    }

    @property final bool empty() const nothrow
    {
        return length == 0;
    }

    @property final size_t length() const nothrow
    {
        return _buffer.data.length;
    }

protected:
    pragma(inline, true)
    final void reserve(size_t count)
    {
        auto c = length + count;
        if (c > _buffer.capacity)
            _buffer.reserve(c + (c >> 1));
    }

protected:
    Appender!(C[]) _buffer;
    XmlEncodeMode _decodeOrEncodeResultMode = XmlEncodeMode.checked;

private:
    XmlBuffer _next;
    XmlBuffer _prev;
}

class XmlBufferList(S = string, Flag!"CheckEncoded" CheckEncoded = No.CheckEncoded) : XmlObject!S
{
@safe:

public:
    alias XmlBufferElement = XmlBuffer!(S, CheckEncoded);
    mixin DLinkTypes!(XmlBufferElement) DLinkXmlBufferElementTypes;

public:
    final XmlBufferElement acquire() nothrow
    {
        if (list.empty)
            return new XmlBufferElement();
        else
            return list.remove(list.last);
    }

    final typeof(this) clear() nothrow
    {
        while (!list.empty)
            list.remove(list.last);
        return this;
    }

    final void release(XmlBufferElement b) nothrow
    {
        list.insertEnd(b.clear());
    }

    pragma(inline, true)
    final S getAndRelease(XmlBufferElement b) nothrow
    {
        auto result = b.value();
        release(b);
        return result;
    }

private:
    DLinkXmlBufferElementTypes.DLinkList list;
}

unittest  // XmlBuffer.decode
{
    import std.exception : assertThrown;

    string s;
    auto buffer = new XmlBuffer!(string, No.CheckEncoded)();

    // Assert that things that should work, do
    s = "hello";
    assert(buffer.clear().decode!(XmlDecodeMode.strict)(s) is s);

    s = buffer.clear().decode!(XmlDecodeMode.loose)("a &gt; b");
    assert(s == "a > b", s);
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("a &lt; b") == "a < b");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("don&apos;t") == "don't");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("&quot;hi&quot;") == "\"hi\"");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("cat &amp; dog") == "cat & dog");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("&#42;") == "*");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("&#x2A;") == "*");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("&lt;&gt;&amp;&apos;&quot;") == "<>&'\"");

    // Assert that things that shouldn't work, don't
    assertThrown!XmlConvertException(buffer.clear().decode!(XmlDecodeMode.strict)("cat & dog"));
    assertThrown!XmlConvertException(buffer.clear().decode!(XmlDecodeMode.strict)("a &gt b"));
    assertThrown!XmlConvertException(buffer.clear().decode!(XmlDecodeMode.strict)("&#;"));
    assertThrown!XmlConvertException(buffer.clear().decode!(XmlDecodeMode.strict)("&#x;"));
    assertThrown!XmlConvertException(buffer.clear().decode!(XmlDecodeMode.strict)("&#2G;"));
    assertThrown!XmlConvertException(buffer.clear().decode!(XmlDecodeMode.strict)("&#x2G;"));

    s = buffer.clear().decode!(XmlDecodeMode.loose)("cat & dog");
    assert(s == "cat & dog", s);
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("a &gt b") == "a &gt b");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("&#;") == "&#;");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("&#x;") == "&#x;");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("&#2G;") == "&#2G;");
    assert(buffer.clear().decode!(XmlDecodeMode.loose)("&#x2G;") == "&#x2G;");
}

unittest  // XmlBuffer.encode
{
    string s;
    auto buffer = new XmlBuffer!(string, No.CheckEncoded)();

    s = "hello";
    assert(buffer.clear().encode(s) is s); // no change

    s = buffer.clear().encode("a > b");
    assert(s == "a &gt; b", s);
    assert(buffer.clear().encode("a < b") == "a &lt; b");
    assert(buffer.clear().encode("don't") == "don&apos;t");
    assert(buffer.clear().encode("\"hi\"") == "&quot;hi&quot;");
    assert(buffer.clear().encode("cat & dog") == "cat &amp; dog");
}
