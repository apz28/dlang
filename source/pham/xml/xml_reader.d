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

module pham.xml.xml_reader;

import std.range.primitives : back, empty, front, popFront;
import std.traits : hasMember;
import std.typecons : Flag, No, Yes;

debug(debug_pham_xml_xml_reader) import std.stdio : writeln;
import pham.utl.utl_utf8 : nextUTF8Char, nextUTF16Char;
import pham.xml.xml_buffer;
import pham.xml.xml_exception;
import pham.xml.xml_message;
import pham.xml.xml_object;
import pham.xml.xml_string;
import pham.xml.xml_type;
import pham.xml.xml_util;

@safe:

enum UnicodeErrorKind : ubyte
{
    eos = 1,
    invalidCode = 2,
}

abstract class XmlReader(S = string) : XmlObject!S
{
@safe:

public:
    enum isBlockReader = hasMember!(typeof(this), "nextBlock");

public:
    final dchar moveFront()
    in
    {
        assert(!empty);
    }
    do
    {
        const f = front;
        popFront();
        return f;
    }

    /**
     * InputRange method to bring the next character to front.
     * Checks internal stack first, and if empty uses primary buffer.
     */
    final void popFront()
    in
    {
        assert(!empty);
    }
    do
    {
        updateLoc();
        sPos += currentCount;
        decode();
    }

    final S readSpaces()
    {
        static if (isBlockReader)
        {
            while (isSpace(front))
                nameBuffer.put(moveFront());
            return nameBuffer.valueAndClear();
        }
        else
        {
            const pStart = sPos;
            while (isSpace(front))
                popFront();
            return s[pStart..sPos];
        }
    }

    final bool readUntilMarker(out S data, scope const(C)[] untilMarker)
    {
        const c = untilMarker[$ - 1];
        data = null;

        static if (isBlockReader)
        {
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (front == c)
                    {
                        readCurrent(nameBuffer);
                        popFront();
                        return true;
                    }

                    readCurrent(nameBuffer);
                    popFront();
                }

                return false;
            }

            while (readUntilChar())
            {
                if (nameBuffer.rightEqual(untilMarker))
                {
                    data = nameBuffer.dropBack(untilMarker.length).valueAndClear();
                    return true;
                }
            }

            nameBuffer.clear();
        }
        else
        {
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (front == c)
                    {
                        popFront();
                        return true;
                    }

                    popFront();
                }

                return false;
            }

            const pStart = sPos;
            while (readUntilChar())
            {
                if (equalRight!S(s[pStart..sPos], untilMarker))
                {
                    data = s[pStart..sPos - untilMarker.length];
                    return true;
                }
            }
        }

        return false;
    }

    final bool readUntilText(bool checkReservedChar)(out XmlString!S data, scope const(C)[] untilMarker)
    {
        const c = untilMarker[$ - 1];
        data = null;

        static if (isBlockReader)
        {
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (front == c)
                    {
                        readCurrent(textBuffer);
                        popFront();
                        return true;
                    }

                    static if (checkReservedChar)
                    {
                        if (front == '<' || front == '>')
                            return false;
                    }

                    readCurrent(textBuffer);
                    popFront();
                }

                return false;
            }

            while (readUntilChar())
            {
                if (textBuffer.rightEqual(untilMarker))
                {
                    data = textBuffer.dropBack(untilMarker.length).toXmlStringAndClear();
                    return true;
                }

                static if (checkReservedChar)
                {
                    if (front == '<' || front == '>')
                    {
                        textBuffer.clear();
                        return false;
                    }
                }
            }

            textBuffer.clear();
        }
        else
        {
            auto encodedMode = XmlEncodeMode.checked;
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (front == c)
                    {
                        popFront();
                        return true;
                    }

                    static if (checkReservedChar)
                    {
                        if (front == '<' || front == '>')
                            return false;
                    }

                    if (encodedMode == XmlEncodeMode.checked && front == '&')
                        encodedMode = XmlEncodeMode.encoded;

                    popFront();
                }

                return false;
            }

            const pStart = sPos;
            while (readUntilChar())
            {
                if (equalRight!S(s[pStart..sPos], untilMarker))
                {
                    data = XmlString!S(s[pStart..sPos - untilMarker.length], encodedMode);
                    return true;
                }

                static if (checkReservedChar)
                {
                    if (front == '<' || front == '>')
                        return false;
                }
            }
        }

        return false;
    }

    final typeof(this) skipSpaces()
    {
        while (isSpace(front))
            popFront();

        return this;
    }

    /**
     * empty property of InputRange
     */
    pragma(inline, true)
    @property final bool empty() const @nogc nothrow pure
    {
        return _empty;
    }

    /*
     * front property of InputRange
     */
    pragma(inline, true)
    @property final dchar front() const @nogc nothrow pure
    {
        return currentChar;
    }

    /*
     * Returns current position (line & column) of processing input
     */
    pragma(inline, true)
    @property final XmlLoc sourceLoc() const @nogc nothrow pure
    {
        return loc;
    }

package:
    pragma(inline, true)
    final bool isAnyFrontBut(const(dchar) c) const nothrow pure
    {
        return !empty && front != c;
    }

    pragma(inline, true)
    final bool isDeclarationNameStart() const nothrow pure
    {
        return !isDeclarationAttributeNameSeparator(front) && isNameStartC(front);
    }

    pragma(inline, true)
    final bool isElementAttributeNameStart() const nothrow pure
    {
        return !isElementAttributeNameSeparator(front) && isNameStartC(front);
    }

    pragma(inline, true)
    final bool isElementTextStart() const nothrow pure
    {
        return !isElementSeparator(front);
    }

    final dchar moveFrontIf(const(dchar) checkNonSpaceChar)
    {
        const f = front;
        if (f == checkNonSpaceChar)
        {
            popFrontColumn();
            return f;
        }
        else
            return 0;
    }

    final S readNameImpl(alias stopChar)(out ParseContext!S name)
    {
        name.loc = loc;
        static if (isBlockReader)
        {
            while (!stopChar(front))
            {
                readCurrent(nameBuffer);
                popFrontColumn();
            }
            name.s = nameBuffer.valueAndClear();
        }
        else
        {
            const pStart = sPos;
            while (!stopChar(front))
                popFrontColumn();
            name.s = s[pStart..sPos];
        }

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, XmlMessage.eBlankName);

        debug(debug_pham_xml_xml_reader) debug writeln(__FUNCTION__, "(name=", name.s, ", line=", name.loc.sourceLine,
            ", column=", name.loc.sourceColumn, ", nline=", loc.sourceLine, ", ncolumn=", loc.sourceColumn);

        return name.s;
    }

    final S readAnyName(out ParseContext!S name)
    {
        return readNameImpl!isNameSeparator(name);
    }

    static if (!isBlockReader)
    pragma(inline, true)
    final void readCurrent(Buffer)(Buffer buffer)
    {
        static if (is(C == dchar))
            buffer.put(front);
        else
            buffer.put(currentCodes());
    }

    final S readDeclarationAttributeName(out ParseContext!S name)
    {
        return readNameImpl!isDeclarationAttributeNameSeparator(name);
    }

    final S readDocumentTypeAttributeListChoiceName(out ParseContext!S name)
    {
        return readNameImpl!isDocumentTypeAttributeListChoice(name);
    }

    final S readDocumentTypeElementChoiceName(out ParseContext!S name)
    {
        return readNameImpl!isDocumentTypeElementChoice(name);
    }

    final S readElementEName(out ParseContext!S name)
    {
        name.loc = loc;
        const first = front;
        static if (isBlockReader)
        {
            // Potential comment or cdata section
            if (first == '-' || first == '[')
            {
                readCurrent(nameBuffer);
                popFrontColumn();
            }

            if (front == '-')
            {
                readCurrent(nameBuffer);
                popFrontColumn();
            }
            else
            {
                while (!isElementENameSeparator(front))
                {
                    readCurrent(nameBuffer);
                    popFrontColumn();
                }

                // Potential cdata section?
                if (first == '[' && front == '[')
                {
                    readCurrent(nameBuffer);
                    popFrontColumn();
                }
            }

            name.s = nameBuffer.valueAndClear();
        }
        else
        {
            auto pStart = sPos;

            // Potential comment or cdata section
            if (first == '-' || first == '[')
                popFrontColumn();

            if (front == '-')
                popFrontColumn();
            else
            {
                while (!isElementENameSeparator(front))
                    popFrontColumn();

                // Potential cdata section?
                if (first == '[' && front == '[')
                    popFrontColumn();
            }

            name.s = s[pStart..sPos];
        }

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, XmlMessage.eBlankName);

        debug(debug_pham_xml_xml_reader) debug writeln(__FUNCTION__, "(name=", name.s, 
            ", line=", name.loc.sourceLine, ", column=", name.loc.sourceColumn, ", nline=", loc.sourceLine, ", ncolumn=", loc.sourceColumn);

        return name.s;
    }

    final S readElementPName(out ParseContext!S name)
    {
        return readNameImpl!isElementPNameSeparator(name);
    }

    final S readElementXAttributeName(out ParseContext!S name)
    {
        return readNameImpl!isElementAttributeNameSeparator(name);
    }

    final S readElementXName(out ParseContext!S name)
    {
        return readNameImpl!isElementXNameSeparator(name);
    }

    final void readElementXText(out XmlString!S text, out bool allWhitespaces)
    {
        allWhitespaces = true;

        static if (isBlockReader)
        {
            while (!isElementTextSeparator(front))
            {
                if (allWhitespaces && !isSpace(front))
                    allWhitespaces = false;
                // encodedMode is checked when put char into buffer
                readCurrent(textBuffer);
                popFront();
            }

            text = textBuffer.toXmlStringAndClear();
        }
        else
        {
            auto encodedMode = XmlEncodeMode.checked;
            const pStart = sPos;
            while (!isElementTextSeparator(front))
            {
                if (allWhitespaces && !isSpace(front))
                    allWhitespaces = false;
                if (encodedMode == XmlEncodeMode.checked && front == '&')
                    encodedMode = XmlEncodeMode.encoded;
                popFront();
            }
            text = XmlString!S(s[pStart..sPos], encodedMode);
        }
    }

protected:
    final S currentCodes() nothrow pure
    in
    {
        assert(!empty);
    }
    do
    {
        return s[sPos..sPos + currentCount];
    }

    final void decode()
    {
        void emptyDecode()
        {
            currentChar = 0;
            currentCount = 0;
            _empty = true;
            /*
            static if (is(C == dchar))
                throw new XmlConvertException(XmlMessage.eInvalidUtf32SequenceEos);
            else static if (is(C == wchar))
                throw new XmlConvertException(XmlMessage.eInvalidUtf16SequenceEos);
            else
                throw new XmlConvertException(XmlMessage.eInvalidUtf8SequenceEos);
            */
        }

        static if (isBlockReader)
        {
            if (needNextBlock() && !nextBlock())
                return emptyDecode();
        }

        if (sPos >= sLen)
            return emptyDecode();

        static if (is(C == dchar))
        {
            currentChar = s[sPos];
            currentCount = 1;
        }
        else static if (is(C == wchar))
        {
            if (!nextUTF16Char(s, sPos, currentChar, currentCount))
                throw new XmlConvertException(XmlMessage.eInvalidUtf16SequenceCode);
        }
        else
        {
            if (!nextUTF8Char(s, sPos, currentChar, currentCount))
                throw new XmlConvertException(XmlMessage.eInvalidUtf8SequenceCode);
        }
    }

    static if (isBlockReader)
    final void initBuffers()
    {
        nameBuffer = new XmlBuffer!(S, No.CheckEncoded);
        textBuffer = new XmlBuffer!(S, Yes.CheckEncoded);
    }

    final void popFrontColumn()
    in
    {
        assert(!empty);
    }
    do
    {
        loc.column += 1;
        sPos += currentCount;
        decode();
    }

    final void updateLoc() nothrow pure
    {
        const f = front;
        if (f == 0xD) // '\n'
        {
            loc.column = 0;
            loc.line += 1;
        }
        else if (f != 0xA)
            loc.column += 1;
    }

    pragma(inline, true)
    static bool isDocumentTypeAttributeListChoice(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '|' || c == '(' || c == ')'
            || isSpace(c);
    }

    pragma(inline, true)
    static bool isDeclarationAttributeNameSeparator(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '?' || c == '='
            || isSpace(c);
    }

    pragma(inline, true)
    static bool isDocumentTypeElementChoice(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == ']' || c == '*' || c == '+'
            || c == '|' || c == ',' || c == '(' || c == ')'
            || isSpace(c);
    }

    pragma(inline, true)
    static bool isElementAttributeNameSeparator(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '/' || c == '='
            || isSpace(c);
    }

    pragma(inline, true)
    static bool isElementENameSeparator(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '!' || c == '['
            || isSpace(c);
    }

    pragma(inline, true)
    static bool isElementPNameSeparator(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '?'
            || isSpace(c);
    }

    pragma(inline, true)
    static bool isElementXNameSeparator(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '/'
            || isSpace(c);
    }

    pragma(inline, true)
    static bool isElementSeparator(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>';
    }

    pragma(inline, true)
    static bool isElementTextSeparator(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<';
    }

    pragma(inline, true)
    static bool isNameSeparator(const(dchar) c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>'
            || isSpace(c);
    }

protected:
    S s;
    size_t sLen, sPos;
    XmlLoc loc;
    static if (isBlockReader)
    {
        XmlBuffer!(S, No.CheckEncoded) nameBuffer;
        XmlBuffer!(S, Yes.CheckEncoded) textBuffer;
    }
    dchar currentChar = 0;
    ubyte currentCount;
    bool _empty;
}

class XmlStringReader(S = string) : XmlReader!S
{
@safe:

public:
    this(S str)
    {
        this.s = str;
        this.sLen = str.length;
        this._empty = str.length == 0;

        if (!this._empty)
            decode();
    }
}

class XmlFileReader(S = string) : XmlReader!S
{
@safe:

import std.file;
import std.stdio;
import std.algorithm.comparison : max;

public:
    this(string fileName, ushort bufferKSize = 64)
    {
        this._fileName = fileName;
        fileHandle.open(fileName);
        this.sBuffer.length = 1_024 * max(bufferKSize, 8);
        static if (isBlockReader)
            initBuffers();

        if (nextBlock())
            decode();
    }

    ~this()
    {
        close();
    }

    final void close()
    {
        if (fileHandle.isOpen())
            fileHandle.close();

        sLen = sPos = currentCount = 0;
        currentChar = 0;
        _empty = true;
    }

    @property final string fileName() const nothrow
    {
        return _fileName;
    }

protected:
    pragma(inline, true)
    final bool needNextBlock() const @nogc nothrow pure
    {
        return sPos + 6 >= sLen;
    }

    final bool nextBlock()
    {
        // Full buffer read?
        if (sLen == 0 || sPos >= sLen)
        {
            s = (() @trusted => fileHandle.rawRead(sBuffer))();
            sPos = 0;
            sLen = s.length;
        }
        // Partial buffer read?
        else
        {
            const left = sLen - sPos;
            sBuffer[0..left] = sBuffer[sPos..sLen];
            auto s2 = (() @trusted => fileHandle.rawRead(sBuffer[left..$]))();
            sPos = 0;
            sLen = left + s2.length;
        }

        _empty = sLen == 0;
        return !_empty;
    }

protected:
    File fileHandle;
    string _fileName;
    C[] sBuffer;
}

package(pham.xml) struct ParseContext(S)
if (isXmlString!S)
{
@safe:

    alias C = XmlChar!S;

    S s;
    XmlLoc loc;
}
