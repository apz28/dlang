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

module pham.xml.reader;

import std.traits : hasMember;
import std.typecons : Flag, No, Yes;
import std.range.primitives : back, empty, front, popFront;

import pham.utl.utf8;
import pham.xml.type;
import pham.xml.message;
import pham.xml.exception;
import pham.xml.util;
import pham.xml.xmlobject;
import pham.xml.buffer;
import pham.xml.string;

@safe:

enum UnicodeErrorKind : byte
{
    eos = 1,
    invalidCode = 2
}

package struct ParseContext(S)
if (isXmlString!S)
{
@safe:

    alias C = XmlChar!S;

    const(C)[] s;
    XmlLoc loc;
}

abstract class XmlReader(S = string) : XmlObject!S
{
public:
    enum isBlockReader = hasMember!(typeof(this), "nextBlock");

public:
    pragma (inline, true)
    final dchar moveFront()
    {
        const f = current;
        popFront();
        return f;
    }

    /** InputRange method to bring the next character to front.
    Checks internal stack first, and if empty uses primary buffer.
    */
    final void popFront()
    {
        updateLoc();
        current = 0;
        static if (!is(XmlChar!S == dchar) && !isBlockReader)
            currentCodes = null;

        empty; // Advance to next char
    }

    final const(C)[] readSpaces()
    {
        static if (isBlockReader)
        {
            while (isSpace(current))
                nameBuffer.put(moveFront());

            return nameBuffer.valueAndClear();
        }
        else
        {
            const pStart = pPos;
            while (isSpace(current))
                popFront();

            return s[pStart..pPos];
        }
    }

    final bool readUntilMarker(out const(C)[] data, const(C)[] untilMarker)
    {
        const c = untilMarker[$ - 1];
        data = null;

        static if (isBlockReader)
        {
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (current == c)
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
                    if (current == c)
                    {
                        popFront();
                        return true;
                    }

                    popFront();
                }

                return false;
            }

            const pStart = pPos;
            while (readUntilChar())
            {
                if (equalRight!S(s[pStart..pPos], untilMarker))
                {
                    data = s[pStart..pPos - untilMarker.length];
                    return true;
                }
            }
        }

        return false;
    }

    final bool readUntilText(bool checkReservedChar)(out XmlString!S data, const(C)[] untilMarker)
    {
        const c = untilMarker[$ - 1];
        data = null;

        static if (isBlockReader)
        {
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (current == c)
                    {
                        readCurrent(textBuffer);
                        popFront();
                        return true;
                    }

                    static if (checkReservedChar)
                    {
                        if (current == '<' || current == '>')
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
                    if (current == '<' || current == '>')
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
            XmlEncodeMode encodedMode = XmlEncodeMode.checked;
            bool readUntilChar()
            {
                while (!empty)
                {
                    if (current == c)
                    {
                        popFront();
                        return true;
                    }

                    static if (checkReservedChar)
                    {
                        if (current == '<' || current == '>')
                            return false;
                    }

                    if (encodedMode == XmlEncodeMode.checked && current == '&')
                        encodedMode = XmlEncodeMode.encoded;

                    popFront();
                }

                return false;
            }

            const pStart = pPos;
            while (readUntilChar())
            {
                if (equalRight!S(s[pStart..pPos], untilMarker))
                {
                    data = XmlString!S(s[pStart..pPos - untilMarker.length], encodedMode);
                    return true;
                }

                static if (checkReservedChar)
                {
                    if (current == '<' || current == '>')
                        return false;
                }
            }
        }

        return false;
    }

    final auto skipSpaces()
    {
        while (isSpace(current))
            popFront();

        return this;
    }

    /** empty property of InputRange
    */
    @property abstract bool empty();

    /* front property of InputRange
    */
    pragma (inline, true)
    @property final dchar front() const nothrow
    {
        return current;
    }

    /* Returns current position (line & column) of processing input
    */
    pragma (inline, true)
    @property final XmlLoc sourceLoc() const nothrow
    {
        return loc;
    }

package:
    pragma (inline, true)
    final bool isAnyFrontBut(dchar c) nothrow
    {
        return current != 0 && current != c;
    }

    pragma (inline, true)
    final bool isDeclarationNameStart()
    {
        return !isDeclarationAttributeNameSeparator(current) && isNameStartC(current);
    }

    pragma (inline, true)
    final bool isElementAttributeNameStart()
    {
        return !isElementAttributeNameSeparator(current) && isNameStartC(current);
    }

    pragma (inline, true)
    final bool isElementTextStart()
    {
        return !isElementSeparator(current);
    }

    final dchar moveFrontIf(dchar aCheckNonSpaceChar)
    {
        const f = front();
        if (f == aCheckNonSpaceChar)
        {
            popFrontColumn();
            return f;
        }
        else
            return 0;
    }

    final const(C)[] readNameImpl(alias stopChar)(out ParseContext!S name)
    {
        name.loc = loc;
        static if (isBlockReader)
        {
            while (!stopChar(current))
            {
                readCurrent(nameBuffer);
                popFrontColumn();
            }
            name.s = nameBuffer.valueAndClear();
        }
        else
        {
            const pStart = pPos;
            while (!stopChar(current))
                popFrontColumn();
            name.s = s[pStart..pPos];
        }

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, XmlMessage.eBlankName);

        version (unittest)
        outputXmlTraceParserF("readNameImpl: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d",
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        return name.s;
    }

    final const(C)[] readAnyName(out ParseContext!S name)
    {
        return readNameImpl!isNameSeparator(name);
    }

    static if (!isBlockReader)
    final void readCurrent(Buffer)(Buffer buffer)
    {
        static if (is(C == dchar))
            buffer.put(current);
        else
        {
            if (currentCodes.length == 1)
                buffer.put(cast(C)current);
            else
                buffer.put(currentCodes);
        }
    }

    final const(C)[] readDeclarationAttributeName(out ParseContext!S name)
    {
        return readNameImpl!isDeclarationAttributeNameSeparator(name);
    }

    final const(C)[] readDocumentTypeAttributeListChoiceName(out ParseContext!S name)
    {
        return readNameImpl!isDocumentTypeAttributeListChoice(name);
    }

    final const(C)[] readDocumentTypeElementChoiceName(out ParseContext!S name)
    {
        return readNameImpl!isDocumentTypeElementChoice(name);
    }

    final const(C)[] readElementEName(out ParseContext!S name)
    {
        name.loc = loc;
        immutable first = current;
        static if (isBlockReader)
        {
            // Potential comment or cdata section
            if (first == '-' || first == '[')
            {
                readCurrent(nameBuffer);
                popFrontColumn();
            }

            if (current == '-')
            {
                readCurrent(nameBuffer);
                popFrontColumn();
            }
            else
            {
                while (!isElementENameSeparator(current))
                {
                    readCurrent(nameBuffer);
                    popFrontColumn();
                }

                // Potential cdata section?
                if (first == '[' && current == '[')
                {
                    readCurrent(nameBuffer);
                    popFrontColumn();
                }
            }

            name.s = nameBuffer.valueAndClear();
        }
        else
        {
            auto pStart = pPos;

            // Potential comment or cdata section
            if (first == '-' || first == '[')
                popFrontColumn();

            if (current == '-')
                popFrontColumn();
            else
            {
                while (!isElementENameSeparator(current))
                    popFrontColumn();

                // Potential cdata section?
                if (first == '[' && current == '[')
                    popFrontColumn();
            }

            name.s = s[pStart..pPos];
        }

        if (name.s.length == 0)
            throw new XmlParserException(name.loc, XmlMessage.eBlankName);

        version (unittest)
        outputXmlTraceParserF("readElementEName: name: %s, line: %d, column: %d, nline: %d, ncolumn: %d",
            name.s, name.loc.sourceLine, name.loc.sourceColumn, loc.sourceLine, loc.sourceColumn);

        return name.s;
    }

    final const(C)[] readElementPName(out ParseContext!S name)
    {
        return readNameImpl!isElementPNameSeparator(name);
    }

    final const(C)[] readElementXAttributeName(out ParseContext!S name)
    {
        return readNameImpl!isElementAttributeNameSeparator(name);
    }

    final const(C)[] readElementXName(out ParseContext!S name)
    {
        return readNameImpl!isElementXNameSeparator(name);
    }

    final void readElementXText(out XmlString!S text, out bool allWhitespaces)
    {
        allWhitespaces = true;

        static if (isBlockReader)
        {
            while (!isElementTextSeparator(current))
            {
                if (allWhitespaces && !isSpace(current))
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
            const pStart = pPos;
            while (!isElementTextSeparator(current))
            {
                if (allWhitespaces && !isSpace(current))
                    allWhitespaces = false;
                if (encodedMode == XmlEncodeMode.checked && current == '&')
                    encodedMode = XmlEncodeMode.encoded;
                popFront();
            }

            text = XmlString!S(s[pStart..pPos], encodedMode);
        }
    }

protected:
    static if (isBlockReader)
    {
        final void initBuffers()
        {
            nameBuffer = new XmlBuffer!(S, No.CheckEncoded);
            textBuffer = new XmlBuffer!(S, Yes.CheckEncoded);
        }
    }

    final void decode()
    in
    {
        assert(sPos < sLen);
    }
    do
    {
        static if (is(C == dchar))
        {
            current = s[sPos++];
        }
        else static if (is(C == wchar))
        {
            void errorUtf16(UnicodeErrorKind errorKind, uint errorCode)
            {
                current = 0;
                static if (!isBlockReader)
                    currentCodes = null;

                if (errorKind == UnicodeErrorKind.eos)
                    throw new XmlConvertException(XmlMessage.eInvalidUtf16SequenceEos);
                else
                    throw new XmlConvertException(XmlMessage.eInvalidUtf16SequenceCode, errorCode);
            }

            void nextBlockUtf16()
            {
                static if (isBlockReader)
                {
                    if (!nextBlock())
                        errorUtf16(UnicodeErrorKind.eos, 0);
                }
                else
                    errorUtf16(UnicodeErrorKind.eos, 0);
            }

            ushort u = s[sPos++];

            if (u >= unicodeSurrogateHighBegin && u <= unicodeSurrogateHighEnd)
            {
                if (sPos >= sLen)
                    nextBlockUtf16();

                current = u;
                static if (!isBlockReader)
                    currentCodeBuffer[0] = u;

                u = s[sPos++];
                static if (!isBlockReader)
                    currentCodeBuffer[1] = u;

                if (u >= unicodeSurrogateLowBegin && u <= unicodeSurrogateLowEnd)
                {
                    current = ((current - unicodeSurrogateHighBegin) << unicodeHalfShift) +
                        (u - unicodeSurrogateLowBegin) + unicodeHalfBase;
                    static if (!isBlockReader)
                        currentCodes = currentCodeBuffer[0..2];
                }
                else
                    errorUtf16(UnicodeErrorKind.invalidCode, u);
            }
            else
            {
                if (u >= unicodeSurrogateLowBegin && u <= unicodeSurrogateLowEnd)
                    errorUtf16(UnicodeErrorKind.invalidCode, u);

                current = u;
                static if (!isBlockReader)
                    currentCodes = s[sPos - 1..sPos];
            }
        }
        else
        {
            /* The following encodings are valid utf8 combinations:
            *  0xxxxxxx
            *  110xxxxx 10xxxxxx
            *  1110xxxx 10xxxxxx 10xxxxxx
            *  11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
            *  111110xx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
            *  1111110x 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx 10xxxxxx
            */

            void errorUtf8(UnicodeErrorKind errorKind, uint errorCode)
            {
                current = 0;
                static if (!isBlockReader)
                    currentCodes = null;

                if (errorKind == UnicodeErrorKind.eos)
                    throw new XmlConvertException(XmlMessage.eInvalidUtf8SequenceEos);
                else
                    throw new XmlConvertException(XmlMessage.eInvalidUtf8SequenceCode, errorCode);
            }

            void nextBlockUtf8()
            {
                static if (isBlockReader)
                {
                    if (!nextBlock())
                        errorUtf8(UnicodeErrorKind.eos, 0);
                }
                else
                    errorUtf8(UnicodeErrorKind.eos, 0);
            }

            ubyte u = s[sPos++];

            if (u & 0x80)
            {
                const extraBytesToRead = unicodeTrailingBytesForUTF8[u];

                if (extraBytesToRead + sPos > sLen)
                {
                    static if (!isBlockReader)
                        errorUtf8(UnicodeErrorKind.eos, 0);
                }

                static if (!isBlockReader)
                    ubyte currentCodeBufferCount = 0;

                switch (extraBytesToRead)
                {
                    case 5:
                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[currentCodeBufferCount++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 4;
                    case 4:
                        if (extraBytesToRead != 4 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[currentCodeBufferCount++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 3;
                    case 3:
                        if (extraBytesToRead != 3 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[currentCodeBufferCount++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 2;
                    case 2:
                        if (extraBytesToRead != 2 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[currentCodeBufferCount++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 1;
                    case 1:
                        if (extraBytesToRead != 1 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        current <<= 6;
                        static if (!isBlockReader)
                            currentCodeBuffer[currentCodeBufferCount++] = u;

                        if (sPos >= sLen)
                            nextBlockUtf8();

                        u = s[sPos++];
                        goto case 0;
                    case 0:
                        if (extraBytesToRead != 0 && (u & 0xC0) != 0x80)
                            errorUtf8(UnicodeErrorKind.invalidCode, u);

                        current += u;
                        static if (!isBlockReader)
                            currentCodeBuffer[currentCodeBufferCount++] = u;
                        break;
                    default:
                        assert(0);
                }

                current -= unicodeOffsetsFromUTF8[extraBytesToRead];
                static if (!isBlockReader)
                    currentCodes = currentCodeBuffer[0..currentCodeBufferCount];

                if (current <= dchar.max)
                {
                    if (current >= unicodeSurrogateHighBegin && current <= unicodeSurrogateLowEnd)
                        errorUtf8(UnicodeErrorKind.invalidCode, current);
                }
                else
                    errorUtf8(UnicodeErrorKind.invalidCode, current);
            }
            else
            {
                current = u;
                static if (!isBlockReader)
                    currentCodes = s[sPos - 1..sPos];
            }
        }
    }

    final void popFrontColumn()
    {
        loc.column += 1;
        current = 0;
        static if (!is(XmlChar!S == dchar) && !isBlockReader)
            currentCodes = null;

        empty; // Advance to next char
    }

    final void updateLoc() nothrow
    {
        if (current == 0xD) // '\n'
        {
            loc.column = 0;
            loc.line += 1;
        }
        else if (current != 0xA)
            loc.column += 1;
    }

    pragma (inline, true)
    static bool isDocumentTypeAttributeListChoice(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '|' || c == '(' || c == ')'
            || isSpace(c);
    }

    pragma (inline, true)
    static bool isDeclarationAttributeNameSeparator(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '?' || c == '='
            || isSpace(c);
    }

    pragma (inline, true)
    static bool isDocumentTypeElementChoice(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == ']' || c == '*' || c == '+'
            || c == '|' || c == ',' || c == '(' || c == ')'
            || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementAttributeNameSeparator(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '/' || c == '='
            || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementENameSeparator(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '!' || c == '['
            || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementPNameSeparator(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '?'
            || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementXNameSeparator(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>' || c == '/'
            || isSpace(c);
    }

    pragma (inline, true)
    static bool isElementSeparator(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>';
    }

    pragma (inline, true)
    static bool isElementTextSeparator(dchar c) nothrow pure
    {
        return c == 0 || c == '<';
    }

    pragma (inline, true)
    static bool isNameSeparator(dchar c) nothrow pure
    {
        return c == 0 || c == '<' || c == '>'
            || isSpace(c);
    }

protected:
    const(C)[] s;
    size_t sLen, sPos, pPos;
    dchar current = 0;
    XmlLoc loc;
    static if (!is(C == dchar) && !isBlockReader)
    {
        C[6] currentCodeBuffer;
        const(C)[] currentCodes;
    }
    static if (isBlockReader)
    {
        XmlBuffer!(S, No.CheckEncoded) nameBuffer;
        XmlBuffer!(S, Yes.CheckEncoded) textBuffer;
    }
}

class XmlStringReader(S = string) : XmlReader!S
{
public:
    this(const(XmlChar!S)[] str)
    {
        this.sPos = this.pPos = 0;
        this.sLen = str.length;
        this.s = str;

        // Setup the first char to avoid duplicated check
        empty;
    }

    @property final override bool empty()
    {
        if (current == 0 && sPos < sLen)
        {
            pPos = sPos;
            decode();
        }

        return current == 0 && sPos >= sLen;
    }
}

class XmlFileReader(S = string) : XmlReader!S
{
import std.file;
import std.stdio;
import std.algorithm.comparison : max;

public:
    this(string fileName, ushort bufferKSize = 64)
    {
        this.eof = false;
        this.sLen = this.sPos = this.pPos = 0;
        this.sBuffer.length = 1_024 * max(bufferKSize, 8);
        this._fileName = fileName;
        fileHandle.open(fileName);
        static if (isBlockReader)
            initBuffers();

        empty; // Setup the first char to avoid duplicated check
    }

    ~this()
    {
        close();
    }

    final void close()
    {
        if (fileHandle.isOpen())
            fileHandle.close();
        eof = true;
        sLen = sPos = pPos = 0;
    }

    @property final override bool empty()
    {
        if (current == 0 && !eof)
        {
            if (sPos >= sLen && !nextBlock())
                return true;

            pPos = sPos;
            decode();
        }

        return current == 0 && eof;
    }

    @property final string fileName() const nothrow
    {
        return _fileName;
    }

protected:
    final bool nextBlock()
    {
        if (sLen == s.length)
            s = (() @trusted => fileHandle.rawRead(sBuffer))();
        else
            s = [];
        sPos = pPos = 0;
        sLen = s.length;
        eof = sLen == 0;
        return !eof;
    }

protected:
    File fileHandle;
    string _fileName;
    C[] sBuffer;
    bool eof;
}
