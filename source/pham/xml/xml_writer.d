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

module pham.xml.xml_writer;

import std.range.primitives : back, empty, front, popFront;
import std.typecons : Flag, No, Yes;

debug(debug_pham_xml_xml_writer) import std.stdio : writeln;
import pham.utl.utl_array_append : Appender;
import pham.xml.xml_buffer;
import pham.xml.xml_message;
import pham.xml.xml_object;
import pham.xml.xml_type;
import pham.xml.xml_util;

@safe:

abstract class XmlWriter(S = string) : XmlObject!S
{
@safe:

public:
    final void decOnlyOneNodeText() nothrow
    {
        _onlyOneNodeText--;
    }

    final void decNodeLevel() nothrow
    {
        _nodeLevel--;
    }

    final void incOnlyOneNodeText() nothrow
    {
        _onlyOneNodeText++;
    }

    final void incNodeLevel() nothrow
    {
        _nodeLevel++;
    }

    abstract void put(C c);

    abstract void put(scope const(C)[] s);

    static if (!is(C == dchar))
    {
        final void put(dchar c)
        {
            import std.encoding : encode;

            C[6] b = void;
            const n = encode(c, b);
            put(b[0..n]);
        }
    }

    final typeof(this) putLF()
    {
        debug(debug_pham_xml_xml_writer) debug writeln(__FUNCTION__, "(_nodeLevel=", _nodeLevel, ", _onlyOneNodeText=", _onlyOneNodeText, ")");

        put('\n');
        return this;
    }

    pragma(inline, true)
    final void putIndent()
    {
        put(indentString());
    }

    final void putWithPreSpace(scope const(C)[] s)
    {
        put(' ');
        put(s);
    }

    final void putWithQuote(scope const(C)[] s)
    {
        put('"');
        put(s);
        put('"');
    }

    final void putAttribute(scope const(C)[] name, scope const(C)[] value)
    {
        put(name);
        put("=");
        putWithQuote(value);
    }

    final void putComment(scope const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        if (prettyOutput && text.length != 0 && !isSpace(text.front))
            put("<!-- ");
        else
            put("<!--");
        put(text);
        if (prettyOutput && text.length != 0 && !isSpace(text.back))
            put(" -->");
        else
            put("-->");

        if (prettyOutput)
            putLF();
    }

    final void putCData(scope const(C)[] data)
    {
        if (prettyOutput)
            putIndent();

        put("<![CDATA[");
        put(data);
        put("]]>");

        if (prettyOutput)
            putLF();
    }

    final void putDocumentTypeBegin(scope const(C)[] name, scope const(C)[] publicOrSystem,
        scope const(C)[] publicId, scope const(C)[] text, Flag!"hasChild" hasChild)
    {
        if (prettyOutput)
            putIndent();

        put("<!DOCTYPE ");
        put(name);

        if (publicOrSystem.length != 0)
        {
            putWithPreSpace(publicOrSystem);

            if (publicId.length != 0 && publicOrSystem == XmlConst!S.public_)
            {
                put(' ');
                putWithQuote(publicId);
            }
        }

        if (text.length != 0)
        {
            put(' ');
            putWithQuote(text);
        }

        if (hasChild)
        {
            put(" [");
            if (prettyOutput)
                putLF();
        }
    }

    final void putDocumentTypeEnd(Flag!"hasChild" hasChild)
    {
        if (hasChild)
            put("]>");
        else
            put('>');

        if (prettyOutput)
            putLF();
    }

    final void putDocumentTypeAttributeListBegin(scope const(C)[] name)
    {
        if (prettyOutput)
            putIndent();

        put("<!ATTLIST ");
        put(name);
        put(' ');
    }

    final void putDocumentTypeAttributeListEnd()
    {
        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putDocumentTypeElementBegin(scope const(C)[] name)
    {
        if (prettyOutput)
            putIndent();

        put("<!ELEMENT ");
        put(name);
        put(' ');
    }

    final void putDocumentTypeElementEnd()
    {
        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putElementEmpty(scope const(C)[] name)
    {
        if (prettyOutput)
            putIndent();

        put('<');
        put(name);
        put("/>");

        if (prettyOutput)
            putLF();
    }

    final void putElementEnd(scope const(C)[] name)
    {
        if (prettyOutput && !onlyOneNodeText)
            putIndent();

        put("</");
        put(name);
        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putElementNameBegin(scope const(C)[] name, Flag!"hasAttribute" hasAttribute)
    {
        if (prettyOutput)
            putIndent();

        put('<');
        put(name);
        if (hasAttribute)
            put(' ');
        else
        {
            put('>');

            if (prettyOutput && !onlyOneNodeText)
                putLF();
        }
    }

    final void putElementNameEnd(scope const(C)[] name, Flag!"hasChild" hasChild)
    {
        if (hasChild)
            put('>');
        else
        {
            if (name.front == '?')
                put("?>");
            else
                put("/>");
        }

        if (prettyOutput && !onlyOneNodeText)
            putLF();
    }

    final void putEntityGeneral(scope const(C)[] name, scope const(C)[] publicOrSystem,
        scope const(C)[] publicId, scope const(C)[] notationName, scope const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        put("<!ENTITY ");
        put(name);

        if (publicOrSystem.length != 0)
        {
            putWithPreSpace(publicOrSystem);

            if (publicId.length != 0 && publicOrSystem == XmlConst!S.public_)
            {
                put(' ');
                putWithQuote(publicId);
            }
        }

        if (notationName.length != 0)
            putWithPreSpace(notationName);

        if (text.length != 0)
        {
            if (notationName == XmlConst!S.nData)
                putWithPreSpace(text);
            else
            {
                put(' ');
                putWithQuote(text);
            }
        }

        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putEntityReference(scope const(C)[] name, scope const(C)[] publicOrSystem,
        scope const(C)[] publicId, scope const(C)[] notationName, scope const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        put("<!ENTITY % ");
        put(name);

        if (publicOrSystem.length != 0)
        {
            putWithPreSpace(publicOrSystem);

            if (publicId.length != 0 && publicOrSystem == XmlConst!S.public_)
            {
                put(' ');
                putWithQuote(publicId);
            }
        }

        if (notationName.length != 0)
            putWithPreSpace(notationName);

        if (text.length != 0)
        {
            if (notationName == XmlConst!S.nData)
                putWithPreSpace(text);
            else
            {
                put(' ');
                putWithQuote(text);
            }
        }

        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putNotation(scope const(C)[] name, scope const(C)[] publicOrSystem,
        scope const(C)[] publicId, scope const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        put("<!NOTATION ");
        put(name);

        if (publicOrSystem.length != 0)
        {
            putWithPreSpace(publicOrSystem);

            if (publicId.length > 0 && publicOrSystem == XmlConst!S.public_)
            {
                put(' ');
                putWithQuote(publicId);
            }
        }

        if (text.length != 0)
        {
            put(' ');
            putWithQuote(text);
        }

        put('>');

        if (prettyOutput)
            putLF();
    }

    final void putProcessingInstruction(scope const(C)[] target, scope const(C)[] text)
    {
        if (prettyOutput)
            putIndent();

        put("<?");
        put(target);
        putWithPreSpace(text);
        put("?>");

        if (prettyOutput)
            putLF();
    }

    @property final bool onlyOneNodeText() const nothrow
    {
        return _onlyOneNodeText != 0;
    }

    @property final size_t nodeLevel() const nothrow
    {
        return _nodeLevel;
    }

    @property final bool prettyOutput() const nothrow
    {
        return _prettyOutput;
    }

protected:
    pragma(inline, true)
    final S indentString() nothrow
    {
        return stringOfChar!S(' ', _nodeLevel << 1);
    }

protected:
    size_t _nodeLevel;
    size_t _onlyOneNodeText;
    bool _prettyOutput;
}

class XmlStringWriter(S = string) : XmlWriter!S
{
@safe:

public:
    this(Flag!"prettyOutput" prettyOutput,
         size_t capacity = 64000) nothrow
    {
        this(prettyOutput, new XmlBuffer!(S, No.CheckEncoded)(capacity));
    }

    this(Flag!"prettyOutput" prettyOutput, XmlBuffer!(S, No.CheckEncoded) buffer) nothrow
    {
        this._prettyOutput = prettyOutput;
        this.buffer = buffer;
    }

    final override void put(C c)
    {
        buffer.put(c);
    }

    final override void put(scope const(C)[] s)
    {
        debug(debug_pham_xml_xml_writer) debug writeln(__FUNCTION__, "(_nodeLevel=", _nodeLevel, ", _onlyOneNodeText=", _onlyOneNodeText, ", s=", s, ")");

        buffer.put(s);
    }

protected:
    XmlBuffer!(S, No.CheckEncoded) buffer;
}

class XmlFileWriter(S = string) : XmlWriter!S
{
    import std.file;
    import std.stdio;
    import std.algorithm.comparison : max;
    
@safe:

public:
    this(string fileName, Flag!"prettyOutput" prettyOutput,
         ushort bufferKSize = 64)
    {
        this._prettyOutput = prettyOutput;
        this._maxBufferSize = 1024 * max(bufferKSize, 8);
        this._buffer.reserve(_maxBufferSize);
        this._fileName = fileName;
        this.fileHandle.open(fileName, "wb");
    }

    ~this()
    {
        close();
    }

    final void close()
    {
        if (fileHandle.isOpen())
        {
            flush();
            fileHandle.close();
        }
    }

    final void flush()
    {
        if (_buffer.data.length != 0)
            doFlush();
    }

    final override void put(C c)
    {
        _buffer.put(c);
        if (_buffer.data.length >= _maxBufferSize)
            doFlush();
    }

    final override void put(scope const(C)[] s)
    {
        _buffer.put(s);
        if (_buffer.data.length >= _maxBufferSize)
            doFlush();
    }

    @property final string fileName() const nothrow
    {
        return _fileName;
    }

protected:
    final void doFlush()
    {
        fileHandle.write(_buffer.data);
        _buffer.clear();
    }

protected:
    File fileHandle;
    string _fileName;
    Appender!(C[]) _buffer;
    size_t _maxBufferSize;
}
