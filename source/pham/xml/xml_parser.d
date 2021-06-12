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

module pham.xml.parser;

import std.conv : to;
import std.range.primitives : back, empty, front, popFront, popBack;
import std.string : indexOf;
import std.typecons : Flag, No, Yes;

import pham.xml.type;
import pham.xml.message;
import pham.xml.exception;
import pham.xml.util;
import pham.xml.xmlobject;
import pham.xml.buffer;
import pham.xml.string;
import pham.xml.reader;
import pham.xml.dom;

@safe:

struct XmlParser(S, Flag!"SAX" SAX = No.SAX)
if (isXmlString!S)
{
@safe:

public:
    alias C = XmlChar!S;

public:
    @disable this();

    this(XmlDocument!S document, XmlReader!S reader, XmlParseOptions!S options) nothrow
    {
        this.document = document;
        this.reader = reader;
        this.options = options;

        static if (SAX)
        {
            useSaxAttribute = options.onSaxAttributeNode !is null;
            useSaxElementBegin = options.onSaxElementNodeBegin !is null;
            useSaxElementEnd = options.onSaxElementNodeEnd !is null;
            useSaxOtherNode = options.onSaxOtherNode !is null;
        }

        nodeStack.reserve(defaultXmlLevels);
    }

    XmlDocument!S parse()
    {
        version (xmlTraceParser)
        outputXmlTraceParser("parse");

        nodeStack.length = 0;
        (() @trusted => nodeStack.assumeSafeAppend())();
        pushNode(document);

        try
        {
            while (!reader.empty)
            {
                if (isSpace(reader.front))
                {
                    if (nodeStack.length == 1)
                        reader.skipSpaces();
                    else
                        parseSpaces();
                    if (reader.empty)
                        break;
                }
                expectChar!(0)('<');
                parseElement();
            }
        }
        catch (XmlException e)
        {
            if (reader is null || isClassType!XmlParserException(e))
                throw e;
            else
                throw new XmlParserException(reader.sourceLoc, e.msg, e);
        }

        if (nodeStack.length != 1)
            throw new XmlParserException(XmlMessage.eEos);

        return document;
    }

private:
    version (xmlTraceParser)
    {
        size_t nodeIndent;

        final string indentString()
        {
            return stringOfChar!string(' ', nodeIndent << 1);
        }
    }

    void expectChar(size_t skipSpaces)(dchar c)
    {
        static if ((skipSpaces & skipSpaceBefore))
            reader.skipSpaces();

        if (reader.empty)
            throw new XmlParserException(XmlMessage.eExpectedCharButEos, c);

        if (reader.moveFrontIf(c) == 0)
            throw new XmlParserException(reader.sourceLoc, XmlMessage.eExpectedCharButChar, c, reader.front);

        static if ((skipSpaces & skipSpaceAfter))
            reader.skipSpaces();
    }

    dchar expectChar(size_t skipSpaces)(S oneOfChars)
    {
        static if ((skipSpaces & skipSpaceBefore))
            reader.skipSpaces();

        if (reader.empty)
            throw new XmlParserException(XmlMessage.eExpectedOneOfCharsButEos, oneOfChars);

        auto c = reader.front;

        if (oneOfChars.indexOf(c) < 0)
            throw new XmlParserException(reader.sourceLoc, XmlMessage.eExpectedOneOfCharsButChar, oneOfChars, c);

        reader.popFront();

        static if ((skipSpaces & skipSpaceAfter))
            reader.skipSpaces();

        return c;
    }

    pragma (inline, true)
    XmlNode!S peekNode()
    in
    {
        assert(!nodeStack.empty);
    }
    do
    {
        return nodeStack.back;
    }

    pragma (inline, true)
    XmlNode!S popNode()
    in
    {
        assert(!nodeStack.empty);
    }
    do
    {
        auto n = nodeStack.back;
        nodeStack.popBack();
        return n;
    }

    XmlNode!S pushNode(XmlNode!S n)
    in
    {
        assert(n !is null);
    }
    do
    {
        nodeStack ~= n;
        return n;
    }

    void parseCData(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseCData.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        const(C)[] data;
        if (!reader.readUntilMarker(data, "]]>"))
        {
            if (reader.empty)
                throw new XmlParserException(XmlMessage.eExpectedStringButEos, "]]>");
            else
                throw new XmlParserException(reader.sourceLoc, XmlMessage.eExpectedStringButNotFound, "]]>");
        }

        auto parentNode = peekNode();
        auto node = document.createCData(data);
        if (options.validate)
            parentNode.checkChild(node, "appendChild()");

        static if (SAX)
        {
            if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                parentNode.appendChild(node);
        }
        else
            parentNode.appendChild(node);
    }

    void parseComment(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseComment.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        const(C)[] data;
        if (!reader.readUntilMarker(data, "-->"))
        {
            if (reader.empty)
                throw new XmlParserException(XmlMessage.eExpectedStringButEos, "-->");
            else
                throw new XmlParserException(reader.sourceLoc, XmlMessage.eExpectedStringButNotFound, "-->");
        }

        auto parentNode = peekNode();
        auto node = document.createComment(data);
        if (options.validate)
            parentNode.checkChild(node, "appendChild()");

        static if (SAX)
        {
            if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                parentNode.appendChild(node);
        }
        else
            parentNode.appendChild(node);
    }

    void parseDeclaration(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseDeclaration.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto parentNode = peekNode();
        auto node = document.createDeclaration();
        if (options.validate)
            parentNode.checkChild(node, "appendChild()");

        if (reader.skipSpaces().isDeclarationNameStart())
        {
            ParseContext!S attributeName;
            do
            {
                parseAttributeDeclaration(node, attributeName);
            }
            while (reader.skipSpaces().isDeclarationNameStart());
        }

        expectChar!(0)('?');
        expectChar!(0)('>');

        static if (SAX)
        {
            if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                parentNode.appendChild(node);
        }
        else
            parentNode.appendChild(node);
    }

    void parseAttributeDeclaration(XmlDeclaration!S parentNode, ref ParseContext!S contextName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF0("%sparseAttributeDeclaration: ", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = reader.readDeclarationAttributeName(contextName);
        if (options.validate)
        {
            if (!isName!(S, No.AllowEmpty)(name))
                throw new XmlParserException(contextName.loc, XmlMessage.eInvalidName, name);

            if (parentNode.findAttribute(name))
                throw new XmlParserException(contextName.loc, XmlMessage.eAttributeDuplicated, name);
        }

        version (xmlTraceParser)
        outputXmlTraceParserF("'%s'", name);

        expectChar!(skipSpaceBefore | skipSpaceAfter)('=');

        // Value
        auto text = parseQuotedValue();

        auto attribute = document.createAttribute(name, text);
        if (options.validate)
            parentNode.checkAttribute(attribute, "appendAttribute()");

        static if (SAX)
        {
            if (useSaxAttribute && options.onSaxAttributeNode(parentNode, attribute))
                parentNode.appendAttribute(attribute);
        }
        else
            parentNode.appendAttribute(attribute);
    }

    void parseDocumentType(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseDocumentType.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlNode!S documentTypeNode;

        auto name = reader.skipSpaces().readAnyName(localContext);

        auto parentNode = peekNode();

        if (reader.skipSpaces().isAnyFrontBut('['))
        {
            const(C)[] systemOrPublic;
            XmlString!S publicId, text;
            parseExternalId(systemOrPublic, publicId, text, false);

            documentTypeNode = document.createDocumentType(name, systemOrPublic, publicId, text);
            if (options.validate)
                parentNode.checkChild(documentTypeNode, "appendChild()");
            pushNode(documentTypeNode);
        }

        if (reader.skipSpaces().moveFrontIf('['))
        {
            if (documentTypeNode is null)
            {
                documentTypeNode = document.createDocumentType(name);
                if (options.validate)
                    parentNode.checkChild(documentTypeNode, "appendChild()");
                pushNode(documentTypeNode);
            }

            while (true)
            {
                immutable f = reader.skipSpaces().front;
                if (f == '<')
                {
                    reader.popFront();
                    parseElement();
                }
                else if (f == '%')
                {
                    auto entityReferenceName = reader.readAnyName(localContext);

                    auto node = document.createText(entityReferenceName);
                    //if (options.validate)
                    //    documentTypeNode.checkChild(node, "appendChild()");

                    static if (SAX)
                    {
                        if (useSaxOtherNode && options.onSaxOtherNode(documentTypeNode, node))
                            documentTypeNode.appendChild(node);
                    }
                    else
                        documentTypeNode.appendChild(node);
                }
                else
                    break;
            }

            expectChar!(0)(']');
        }

        expectChar!(skipSpaceBefore)('>');

        if (documentTypeNode !is null)
        {
            auto e = popNode();
            assert(e is documentTypeNode);

            static if (SAX)
            {
                if (useSaxOtherNode && options.onSaxOtherNode(parentNode, documentTypeNode))
                    parentNode.appendChild(documentTypeNode);
            }
            else
                parentNode.appendChild(documentTypeNode);
        }
    }

    void parseDocumentTypeAttributeList(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseDocumentTypeAttributeList.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;

        auto name = reader.skipSpaces().readAnyName(localContext);

        auto parentNode = peekNode();
        auto node = document.createDocumentTypeAttributeList(name);
        if (options.validate)
            parentNode.checkChild(node, "appendChild()");

        while (reader.skipSpaces().isAnyFrontBut('>'))
            parseDocumentTypeAttributeListItem(node);

        expectChar!(0)('>');

        static if (SAX)
        {
            if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                parentNode.appendChild(node);
        }
        else
            parentNode.appendChild(node);
    }

    void parseDocumentTypeAttributeListItem(XmlDocumentTypeAttributeList!S attributeList)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseDocumentTypeAttributeListItem", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlString!S defaultText;
        const(C)[] type, defaultType;
        const(C)[][] typeItems;

        auto name = reader.skipSpaces().readAnyName(localContext);

        // EnumerateType
        if (reader.skipSpaces().moveFrontIf('('))
        {
            while (reader.skipSpaces().isAnyFrontBut(')'))
            {
                typeItems ~= reader.readDocumentTypeAttributeListChoiceName(localContext);
                reader.skipSpaces().moveFrontIf('|');
            }
            expectChar!(0)(')');
        }
        else
        {
            type = reader.readAnyName(localContext);

            if (type == XmlConst!S.notation)
            {
                expectChar!(skipSpaceBefore)('(');
                while (reader.skipSpaces().isAnyFrontBut(')'))
                {
                    typeItems ~= reader.readDocumentTypeAttributeListChoiceName(localContext);
                    reader.skipSpaces().moveFrontIf('|');
                }
                expectChar!(0)(')');
            }
        }

        if (reader.skipSpaces().front == '#')
        {
            defaultType = reader.readAnyName(localContext);

            if (defaultType != XmlConst!S.fixed  &&
                defaultType != XmlConst!S.implied &&
                defaultType != XmlConst!S.required)
                throw new XmlParserException(localContext.loc, XmlMessage.eExpectedOneOfStringsButString,
                    XmlConst!string.fixed ~ ", " ~
                    XmlConst!string.implied ~ " or " ~
                    XmlConst!string.required, defaultType);
        }

        if ("\"'".indexOf(reader.skipSpaces().front) >= 0)
            defaultText = parseQuotedValue();

        auto defType = document.createAttributeListDefType(name, type, typeItems);
        auto def = document.createAttributeListDef(defType, defaultType, defaultText);
        attributeList.appendDef(def);
    }

    void parseDocumentTypeElement(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseDocumentTypeElement.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;

        auto name = reader.skipSpaces().readAnyName(localContext);

        auto parentNode = peekNode();
        auto node = document.createDocumentTypeElement(name);
        if (options.validate)
            parentNode.checkChild(node, "appendChild()");

        if (reader.skipSpaces().moveFrontIf('('))
        {
            parseDocumentTypeElementChoice(node, node.appendChoice(""));
        }
        else
        {
            auto choice = reader.readAnyName(localContext);

            if (choice != XmlConst!S.any && choice != XmlConst!S.empty)
                throw new XmlParserException(localContext.loc, XmlMessage.eExpectedOneOfStringsButString,
                    XmlConst!string.any ~ " or " ~ XmlConst!string.empty, choice);

            node.appendChoice(choice);
        }

        expectChar!(skipSpaceBefore)('>');

        static if (SAX)
        {
            if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                parentNode.appendChild(node);
        }
        else
            parentNode.appendChild(node);
    }

    void parseDocumentTypeElementChoice(XmlDocumentTypeElement!S node, XmlDocumentTypeElementItem!S parent)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseDocumentTypeElementChoice", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlDocumentTypeElementItem!S last;
        bool done;

        while (!done && reader.skipSpaces().isAnyFrontBut(')'))
        {
            switch (reader.front)
            {
                case '(':
                    reader.popFront();
                    parseDocumentTypeElementChoice(node, parent.appendChoice(""));
                    break;
                case '?':
                case '*':
                case '+':
                    if (last !is null && last.multiIndicator == 0)
                        last.multiIndicator = cast(XmlChar!S)reader.moveFront();
                    else
                        throw new XmlParserException(reader.sourceLoc, XmlMessage.eMultipleTextFound, reader.front);
                    break;
                case '|':
                case ',':
                    reader.popFront();
                    break;
                case '<':
                case '>':
                case ']':
                    done = true;
                    break;
                default:
                    auto choice = reader.readDocumentTypeElementChoiceName(localContext);
                    last = parent.appendChoice(choice);
                    break;
            }
        }
        expectChar!(skipSpaceBefore | skipSpaceAfter)(')');

        switch (reader.front)
        {
            case '?':
            case '*':
            case '+':
                if (parent.multiIndicator == 0)
                    parent.multiIndicator = cast(XmlChar!S)reader.moveFront();
                else
                    throw new XmlParserException(reader.sourceLoc, XmlMessage.eMultipleTextFound, reader.front);
                break;
            default:
                break;
        }
    }

    void parseElement()
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseElement(%c)", indentString(), reader.front);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S tagName;

        const c = reader.front;
        if (c == '?')
        {
            reader.popFront();
            if (reader.readElementPName(tagName) == "xml")
                parseDeclaration(tagName);
            else
                parseProcessingInstruction(tagName);
        }
        else if (c == '!')
        {
            reader.popFront();
            auto name = reader.readElementEName(tagName);
            if (name == "--")
                parseComment(tagName);
            else if (name == "[CDATA[")
                parseCData(tagName);
            else if (name == "DOCTYPE")
                parseDocumentType(tagName);
            else if (name == "ENTITY")
                parseEntity(tagName);
            else if (name == "ATTLIST")
                parseDocumentTypeAttributeList(tagName);
            else if (name == "ELEMENT")
                parseDocumentTypeElement(tagName);
            else if (name == "NOTATION")
                parseNotation(tagName);
            else
                throw new XmlParserException(tagName.loc, XmlMessage.eInvalidName, '!' ~ name);
        }
        else
        {
            reader.readElementXName(tagName);
            parseElementX(tagName);
        }
    }

    void parseEntity(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseEntity.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlString!S publicId, text;
        const(C)[] systemOrPublic, notationName;
        bool reference;

        if (reader.skipSpaces().moveFrontIf('%'))
        {
            reference = true;
            reader.skipSpaces();
        }

        auto name = reader.readAnyName(localContext);

        if ("\"'".indexOf(reader.skipSpaces().front) >= 0)
        {
            text = parseQuotedValue();
        }
        else
        {
            parseExternalId(systemOrPublic, publicId, text, false);

            if (!reference && reader.skipSpaces().isAnyFrontBut('>'))
            {
                const(C)[] nData = reader.readAnyName(localContext);
                if (nData != XmlConst!S.nData)
                    throw new XmlParserException(localContext.loc, XmlMessage.eExpectedStringButString, XmlConst!string.nData, nData);
                notationName = reader.skipSpaces().readAnyName(localContext);
            }
        }

        expectChar!(skipSpaceBefore)('>');

        auto parentNode = peekNode();
        XmlNode!S node;
        if (reference)
        {
            if (systemOrPublic.length != 0)
                node = document.createEntityReference(name, systemOrPublic, publicId, text);
            else
                node = document.createEntityReference(name, text);
        }
        else
        {
            if (systemOrPublic.length != 0)
                node = document.createEntity(name, systemOrPublic, publicId, text, notationName);
            else
                node = document.createEntity(name, text);
        }
        if (options.validate)
            parentNode.checkChild(node, "appendChild()");

        static if (SAX)
        {
            if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                parentNode.appendChild(node);
        }
        else
            parentNode.appendChild(node);
    }

    void parseElementX(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseElementX.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto name = tagName.s;
        if (options.validate && !isName!(S, No.AllowEmpty)(name))
            throw new XmlParserException(tagName.loc, XmlMessage.eInvalidName, name);

        auto parentNode = peekNode();
        auto element = document.createElement(name);
        if (options.validate)
            parentNode.checkChild(element, "appendChild()");
        pushNode(element);

        static if (SAX)
        {
            if (useSaxElementBegin)
                options.onSaxElementNodeBegin(parentNode, element);
        }

        if (reader.skipSpaces().isElementAttributeNameStart())
        {
            ParseContext!S attributeName;
            do
            {
                parseElementXAttribute(element, attributeName);
            }
            while (reader.skipSpaces().isElementAttributeNameStart());
        }

        if (reader.moveFrontIf('>'))
        {
            if (reader.isElementTextStart())
                parseElementXText(element);

            expectChar!(0)('<');
            while (reader.isAnyFrontBut('/'))
            {
                parseElement();

                if (reader.isElementTextStart())
                    parseElementXText(element);

                expectChar!(0)('<');
            }
            expectChar!(0)('/');
            parseElementXEnd(tagName.s);
        }
        else
        {
            expectChar!(0)('/');
            expectChar!(0)('>');

            auto e = popNode();
            assert(e is element);

            static if (SAX)
            {
                if (useSaxElementEnd && options.onSaxElementNodeEnd(parentNode, element))
                    parentNode.appendChild(element);
            }
            else
                parentNode.appendChild(element);
        }
    }

    void parseElementXAttribute(XmlElement!S parentNode, ref ParseContext!S contextName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF0("%sparseElementXAttribute: ", indentString());
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = reader.readElementXAttributeName(contextName);
        if (options.validate)
        {
            if (!isName!(S, No.AllowEmpty)(name))
                throw new XmlParserException(contextName.loc, XmlMessage.eInvalidName, name);

            if (parentNode.findAttribute(name))
                throw new XmlParserException(contextName.loc, XmlMessage.eAttributeDuplicated, name);
        }

        version (xmlTraceParser)
        outputXmlTraceParserF("'%s'", name);

        expectChar!(skipSpaceBefore | skipSpaceAfter)('=');

        // Value
        auto text = parseQuotedValue();

        auto attribute = document.createAttribute(name, text);
        if (options.validate)
            parentNode.checkAttribute(attribute, "appendAttribute()");

        static if (SAX)
        {
            if (useSaxAttribute && options.onSaxAttributeNode(parentNode, attribute))
                parentNode.appendAttribute(attribute);
        }
        else
            parentNode.appendAttribute(attribute);
    }

    void parseElementXEnd(const(C)[] beginTagName)
    {
        version (xmlTraceParser)
        outputXmlTraceParserF("%sparseElementXEnd.%s", indentString(), beginTagName);

        ParseContext!S endTagName;
        if (reader.readElementXName(endTagName) != beginTagName)
            throw new XmlParserException(endTagName.loc, XmlMessage.eExpectedEndName, beginTagName, endTagName.s);
        expectChar!(skipSpaceBefore)('>');

        auto element = cast(XmlElement!S)popNode();
        auto parentNode = peekNode();

        static if (SAX)
        {
            if (useSaxElementEnd && options.onSaxElementNodeEnd(parentNode, element))
                parentNode.appendChild(element);
        }
        else
            parentNode.appendChild(element);
    }

    void parseElementXText(XmlElement!S parentNode)
    {
        version (xmlTraceParser)
        outputXmlTraceParserF0("%sparseElementXText: ", indentString());

        XmlString!S text;
        bool allWhitespaces;
        reader.readElementXText(text, allWhitespaces);

        version (xmlTraceParser)
        outputXmlTraceParserF("'%s'", text.rawValue().leftStringIndicator!S(30));

        XmlNode!S node;
        if (allWhitespaces)
        {
            if (options.preserveWhitespace)
                node = document.createSignificantWhitespace(text.value);
            //else
            //    node = document.createWhitespace(text.value);
        }
        else
            node = document.createText(text);

        if (node)
        {
            //if (options.validate)
            //    parentNode.checkChild(node, "appendChild()");

            static if (SAX)
            {
                if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                    parentNode.appendChild(node);
            }
            else
                parentNode.appendChild(node);
        }
    }

    void parseExternalId(ref const(C)[] systemOrPublic, ref XmlString!S publicId,
        ref XmlString!S text, bool optionalText)
    {
        version (xmlTraceParser)
        outputXmlTraceParserF("%sparseExternalId", indentString());

        ParseContext!S localContext;

        systemOrPublic = reader.skipSpaces().readAnyName(localContext);
        reader.skipSpaces();

        if (systemOrPublic == XmlConst!S.system)
            text = parseQuotedValue();
        else if (systemOrPublic == XmlConst!S.public_)
        {
            publicId = parseQuotedValue();
            reader.skipSpaces();

            if (!optionalText || reader.isAnyFrontBut('>'))
                text = parseQuotedValue();
        }
        else
            throw new XmlParserException(localContext.loc, XmlMessage.eExpectedOneOfStringsButString,
                XmlConst!string.public_ ~ " or " ~ XmlConst!string.system, systemOrPublic);
    }

    void parseNotation(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseNotation.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        ParseContext!S localContext;
        XmlString!S publicId, text;
        const(C)[] systemOrPublic;

        auto name = reader.skipSpaces().readAnyName(localContext);

        parseExternalId(systemOrPublic, publicId, text, true);

        expectChar!(skipSpaceBefore)('>');

        auto parentNode = peekNode();
        auto node = document.createNotation(name, systemOrPublic, publicId, text);
        if (options.validate)
            parentNode.checkChild(node, "appendChild()");

        static if (SAX)
        {
            if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                parentNode.appendChild(node);
        }
        else
            parentNode.appendChild(node);
    }

    void parseProcessingInstruction(ref ParseContext!S tagName)
    {
        version (xmlTraceParser)
        {
            outputXmlTraceParserF("%sparseProcessingInstruction.%s", indentString(), tagName.s);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // Name
        auto name = tagName.s;
        if (options.validate && !isName!(S, No.AllowEmpty)(name))
            throw new XmlParserException(tagName.loc, XmlMessage.eInvalidName, name);

        XmlString!S data;
        if (!reader.skipSpaces().readUntilText!true(data, "?>"))
        {
            if (reader.empty)
                throw new XmlParserException(XmlMessage.eExpectedStringButEos, "?>");
            else
                throw new XmlParserException(reader.sourceLoc, XmlMessage.eExpectedStringButNotFound, "?>");
        }

        auto parentNode = peekNode();
        auto node = document.createProcessingInstruction(name, data);
        if (options.validate)
            parentNode.checkChild(node, "appendChild()");

        static if (SAX)
        {
            if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                parentNode.appendChild(node);
        }
        else
            parentNode.appendChild(node);
    }

    XmlString!S parseQuotedValue()
    {
        version (xmlTraceParser)
        outputXmlTraceParserF0("%sparseQuotedValue: ", indentString());

        auto q = expectChar!(0)("\"'");
        XmlString!S data;
        if (!reader.readUntilText!false(data, to!S(q)))
            expectChar!(0)(q);

        version (xmlTraceParser)
        outputXmlTraceParserF("'%s'", data.rawValue().leftStringIndicator!S(30));

        return data;
    }

    void parseSpaces()
    {
        version (xmlTraceParser)
        outputXmlTraceParserF("%sparseSpaces", indentString());

        auto s = reader.readSpaces();
        if (options.preserveWhitespace)
        {
            if (nodeStack.length == 1)
            {
                auto node = document.createWhitespace(s);
                if (options.validate)
                    document.checkChild(node, "appendChild()");

                static if (SAX)
                {
                    if (useSaxOtherNode && options.onSaxOtherNode(document, node))
                        document.appendChild(node);
                }
                else
                    document.appendChild(node);
            }
            else
            {
                auto parentNode = peekNode();
                auto node = document.createSignificantWhitespace(s);
                if (options.validate)
                    parentNode.checkChild(node, "appendChild()");

                static if (SAX)
                {
                    if (useSaxOtherNode && options.onSaxOtherNode(parentNode, node))
                        parentNode.appendChild(node);
                }
                else
                    parentNode.appendChild(node);
            }
        }
    }

private:
    enum skipSpaceBefore = 1;
    enum skipSpaceAfter = 2;

    XmlNode!S[] nodeStack;
    XmlDocument!S document;
    XmlReader!S reader;
    const(XmlParseOptions!S) options;

    static if (SAX)
    {
        bool useSaxAttribute;
        bool useSaxElementBegin;
        bool useSaxElementEnd;
        bool useSaxOtherNode;
    }
}

unittest  // XmlParser.invalid construct
{
    import pham.utl.utltest;
    dgWriteln("unittest xml.parser.XmlParser.invalid construct");

    void parseError(string xml)
    {
        try
        {
            auto doc = new XmlDocument!string().load("<");

            assert(0, "never reach here for parseError");
        }
        catch (XmlParserException e)
        {
        }
    }

    parseError("<");
    parseError(">");
    parseError("</>");
    parseError("<!");
    parseError("<!>");
    parseError("<!xyz>");
}

unittest  // XmlParser.DOCTYPE
{
    import pham.utl.utltest;
    dgWriteln("unittest xml.parser.XmlParser.DOCTYPE");

    static immutable string xml =
q"XML
<!DOCTYPE myDoc SYSTEM "http://myurl.net/folder" [
  <!ELEMENT anyElement ANY>
  <!ENTITY replaceText "replacement text">
  <!ATTLIST requireDataFoo foo CDATA #REQUIRED>
]>
XML";

    auto doc = new XmlDocument!string().load(xml);
}

unittest  // XmlParser
{
    import pham.xml_test;
    import pham.utl.utltest;
    dgWriteln("unittest xml.parser.XmlParser");

    auto doc = new XmlDocument!string().load(parserXml);
}

unittest  // XmlParser.navigation
{
    import std.conv : to;
    import std.typecons : No, Yes;
    import pham.utl.utltest;
    dgWriteln("unittest xml.parser.XmlParser.navigation");

    static immutable string xml =
q"XML
    <?xml version="1.0" encoding="UTF-8"?>
    <root>
        <withAttributeOnly att=""/>
        <withAttributeOnly2 att1="1" att2="abc"/>
        <attributeWithNP xmlns:myns="something"/>
        <withAttributeAndChild att1="&lt;&gt;&amp;&apos;&quot;" att2='with double quote ""'>
            <child/>
            <child></child>
        </withAttributeAndChild>
        <childWithText>abcd</childWithText>
        <childWithText2>line &amp; Text</childWithText2>
        <myNS:nodeWithNP/>
        <!-- This is a -- comment -->
        <![CDATA[ dataSection! ]]>
    </root>
XML";

    auto doc = new XmlDocument!string().load(xml);

    dgWriteln("unittest XmlParser - navigation(start walk)");
    dgWriteln("check doc.documentDeclaration");

    assert(doc.documentDeclaration !is null);
    assert(doc.documentDeclaration.innerText = "version=\"1.0\" encoding=\"UTF-8\"");

    dgWriteln("check doc.documentElement");

    assert(doc.documentElement !is null);
    assert(doc.documentElement.nodeType == XmlNodeType.element);
    assert(doc.documentElement.name == "root", doc.documentElement.name);
    assert(doc.documentElement.localName == "root", doc.documentElement.localName);

    XmlNodeList!string L;

    dgWriteln("check doc.documentElement.getChildNodes(deep=true)");

    L = doc.documentElement.getChildNodes(null, Yes.deep);

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeOnly", L.front.name);
    assert(L.front.localName == "withAttributeOnly", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.value == "", L.front.firstAttribute.value);
    assert(L.front.firstAttribute is L.front.lastAttribute);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeOnly2", L.front.name);
    assert(L.front.localName == "withAttributeOnly2", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att1", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.value == "1", L.front.firstAttribute.value);
    assert(L.front.lastAttribute.name == "att2", L.front.lastAttribute.name);
    assert(L.front.lastAttribute.value == "abc", L.front.lastAttribute.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "attributeWithNP", L.front.name);
    assert(L.front.localName == "attributeWithNP", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "xmlns:myns", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.localName == "myns", L.front.firstAttribute.localName);
    assert(L.front.firstAttribute.value == "something", L.front.firstAttribute.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeAndChild", L.front.name);
    assert(L.front.localName == "withAttributeAndChild", L.front.localName);
    assert(L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att1", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.localName == "att1", L.front.firstAttribute.localName);
    assert(L.front.firstAttribute.value == "<>&'\"", L.front.firstAttribute.value);
    assert(L.front.lastAttribute.name == "att2", L.front.lastAttribute.name);
    assert(L.front.lastAttribute.value == "with double quote \"\"", L.front.lastAttribute.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "child", L.front.name);
    assert(L.front.localName == "child", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute is null);
    assert(L.front.lastAttribute is null);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "child", L.front.name);
    assert(L.front.localName == "child", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute is null);
    assert(L.front.lastAttribute is null);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();

        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "childWithText", L.front.name);
    assert(L.front.localName == "childWithText", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.innerText == "abcd", L.front.innerText);
    assert(L.front.firstChild.value == "abcd", L.front.firstChild.value);
    L.popFront();
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "childWithText2", L.front.name);
    assert(L.front.localName == "childWithText2", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.innerText == "line & Text", L.front.innerText);
    assert(L.front.firstChild.value == "line & Text", L.front.firstChild.value);
    L.popFront();
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "myNS:nodeWithNP", L.front.name);
    assert(L.front.localName == "nodeWithNP", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.comment, to!string(L.front.nodeType));
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.value = " This is a -- comment ", L.front.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.CData, to!string(L.front.nodeType));
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.value = " dataSection! ", L.front.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(L.empty);

    outputXmlTraceProgress("check doc.documentElement.childNodes()");

    L = doc.documentElement.childNodes();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeOnly", L.front.name);
    assert(L.front.localName == "withAttributeOnly", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.value == "", L.front.firstAttribute.value);
    assert(L.front.firstAttribute is L.front.lastAttribute);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeOnly2", L.front.name);
    assert(L.front.localName == "withAttributeOnly2", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att1", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.value == "1", L.front.firstAttribute.value);
    assert(L.front.lastAttribute.name == "att2", L.front.lastAttribute.name);
    assert(L.front.lastAttribute.value == "abc", L.front.lastAttribute.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "attributeWithNP", L.front.name);
    assert(L.front.localName == "attributeWithNP", L.front.localName);
    assert(L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "xmlns:myns", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.localName == "myns", L.front.firstAttribute.localName);
    assert(L.front.firstAttribute.value == "something", L.front.firstAttribute.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "withAttributeAndChild", L.front.name);
    assert(L.front.localName == "withAttributeAndChild", L.front.localName);
    assert(L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.firstAttribute.name == "att1", L.front.firstAttribute.name);
    assert(L.front.firstAttribute.localName == "att1", L.front.firstAttribute.localName);
    assert(L.front.firstAttribute.value == "<>&'\"", L.front.firstAttribute.value);
    assert(L.front.lastAttribute.name == "att2", L.front.lastAttribute.name);
    assert(L.front.lastAttribute.value == "with double quote \"\"", L.front.lastAttribute.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "childWithText", L.front.name);
    assert(L.front.localName == "childWithText", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.innerText == "abcd", L.front.innerText);
    assert(L.front.firstChild.value == "abcd", L.front.firstChild.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "childWithText2", L.front.name);
    assert(L.front.localName == "childWithText2", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(L.front.hasChildNodes);
    assert(L.front.innerText == "line & Text", L.front.innerText);
    assert(L.front.firstChild.value == "line & Text", L.front.firstChild.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.element, to!string(L.front.nodeType));
    assert(L.front.name == "myNS:nodeWithNP", L.front.name);
    assert(L.front.localName == "nodeWithNP", L.front.localName);
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.comment, to!string(L.front.nodeType));
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.value = " This is a -- comment ", L.front.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(!L.empty);
    assert(L.front.nodeType == XmlNodeType.CData, to!string(L.front.nodeType));
    assert(!L.front.hasAttributes);
    assert(!L.front.hasChildNodes);
    assert(L.front.value = " dataSection! ", L.front.value);
    L.popFront();

    version (none)
    if (doc.parseOptions.preserveWhitespace)
    {
        assert(!L.empty);
        assert(L.front.nodeType == XmlNodeType.whitespace, to!string(L.front.nodeType));
        L.popFront();
    }

    assert(L.empty);
}

unittest  // XmlParser.SAX
{
    import pham.xml.test;
    import pham.utl.utltest;
    dgWriteln("unittest xml.parser.XmlParser.SAX");

    version (none)
    static bool processAttribute(XmlNode!string parent, XmlAttribute!string attribute)
    {
        // return true to keep the attribute, however if its parent node is discarded,
        // the attribute will also be discarded at the end
        // return false to discard the attribute
        return false;
    }

    version (none)
    static void processElementBegin(XmlNode!string parent, XmlElement!string element)
    {}

    static bool processElementEnd(XmlNode!string parent, XmlElement!string element)
    {
        // return true to keep the element, however if its parent node is discarded,
        // the element will also be discarded at the end
        // return false to discard the element

        // Only keep elements with localName = "bookstore" | "book" | "title"
        auto localName = element.localName;
        return localName == "bookstore" ||
            localName == "book" ||
            localName == "title";
    }

    static bool processOtherNode(XmlNode!string parent, XmlNode!string node)
    {
        // return true to keep the node, however if its parent node is discarded,
        // the node will also be discarded at the end
        // return false to discard the node

        return node.nodeType == XmlNodeType.text;
    }

    XmlParseOptions!string options;
    version (none)
    options.onSaxAttributeNode = &processAttribute;
    version (none)
    options.onSaxElementNodeBegin = &processElementBegin;
    options.onSaxElementNodeEnd = &processElementEnd;
    options.onSaxOtherNode = &processOtherNode;

    auto doc = new XmlDocument!string();

    doc.load!(Yes.SAX)(parserSaxXml, options);

    assert(doc.outerXml() == "<bookstore><book><title>Pride And Prejudice</title></book><book><title>The Handmaid's Tale</title></book></bookstore>");
}
