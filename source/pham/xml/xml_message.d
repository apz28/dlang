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

module pham.xml.xml_message;

import pham.xml.xml_type;

nothrow @safe:

struct XmlMessage
{
nothrow @safe:

public:
    static immutable eBlankName = "Name is blank";
    static immutable eEos = "Incompleted xml data";
    static immutable eExpectedCharButChar = `Expect character "%c" but found "%c"`;
    static immutable eExpectedCharButEos = `Expect character "%c" but incompleted data`;
    static immutable eExpectedEndName = `Expect end element name "%s" but found "%s"`;
    static immutable eExpectedStringButEos = `Expect string "%s" but incompleted data`;
    static immutable eExpectedStringButNotFound = `Expect string "%s" but not found`;
    static immutable eExpectedStringButString = `Expect string "%s" but found "%s"`;
    static immutable eExpectedOneOfCharsButChar = `Expect one of characters "%s" but found "%c"`;
    static immutable eExpectedOneOfCharsButEos = `Expect one of characters "%s" but incompleted data`;
    static immutable eExpectedOneOfStringsButString = `Expect one of "%s" but found "%s"`;
    static immutable eInvalidArgTypeOf = `Invalid argument type at "%d" for %s; data "%s"`;
    static immutable eInvalidName = `Invalid name "%s"`;
    static immutable eInvalidNameAtOf = `Invalid name at "%d"; data "%s"`;
    //static immutable eInvalidNumArgs = `Invalid number of arguments "%d/%d" of %s`;
    static immutable eInvalidNumberArgsOf = `Invalid number of arguments "%d" [expected %d] for %s; data "%s"`;
    static immutable eInvalidOpDelegate = "Invalid operation %s.%s";
    static immutable eInvalidOpFunction = "Invalid operation %s";
    static immutable eInvalidOpFromWrongParent = "Invalid operation %s.%s of different parent node";
    static immutable eInvalidTokenAtOf = `Invalid token "%c" at "%d"; data "%s"`;
    static immutable eInvalidTypeValueOf2 = `Invalid %s value [%s, %s]: "%s"`;
    static immutable eInvalidUtf8SequenceEos = "Invalid UTF8 sequence - end of stream";
    static immutable eInvalidUtf8SequenceCode = "Invalid UTF8 sequence - invalid code %d";
    static immutable eInvalidUtf16SequenceEos = "Invalid UTF16 sequence - end of stream";
    static immutable eInvalidUtf16SequenceCode = "Invalid UTF16 sequence - invalid code";
    static immutable eInvalidUtf32SequenceEos = "Invalid UTF32 sequence - end of stream";
    static immutable eInvalidVariableName = `Invalid variable name "%s"`;
    static immutable eInvalidVersionStr = `Invalid version string "%s"`;
    static immutable eMultipleTextFound = `Multiple "%s" found`;
    static immutable eNodeSetExpectedAtOf = `NodeSet is expected at "%d"; data "%s"`;
    static immutable eNotAllWhitespaces = "Not all whitespace characters";
    static immutable eNotAllowChild = `Invalid operation %s.%s. "%s" [node type "%d"] not allow child "%s" [node type "%d"]`;
    static immutable eNotAllowAppendDifDoc = `Not allow appending "%s" with different owner document`;
    static immutable eNotAllowAppendSelf = "Not allow appending self as child";
    static immutable eAttributeDuplicated = `Not allow to append duplicated attribute "%s"`;
    static immutable eAttributeListChanged = "Attribute list had changed since start enumerated";
    static immutable eChildListChanged = "Child list had changed since start enumerated";
    static immutable eExpressionTooComplex = `Expression is too complex "%s"`;
    static immutable eUnescapeAndChar = `Unescaped "&" character`;

    static immutable atLineInfo = " at line %d position %d";
}

struct XmlConst(S)
if (isXmlString!S)
{
nothrow @safe:

public:
    static immutable S CDataTagName = "#cdata-section";
    static immutable S commentTagName = "#comment";
    static immutable S declarationTagName = "xml";
    static immutable S documentFragmentTagName = "#document-fragment";
    static immutable S documentTagName = "#document";
    //static immutable S entityTagName = "#entity";
    //static immutable S notationTagName = "#notation";
    static immutable S significantWhitespaceTagName = "#significant-whitespace";
    static immutable S textTagName = "#text";
    static immutable S whitespaceTagName = "#whitespace";

    static immutable S declarationEncodingName = "encoding";
    static immutable S declarationStandaloneName = "standalone";
    static immutable S declarationVersionName = "version";

    static immutable S yes = "yes";
    static immutable S no = "no";

    static immutable S any = "ANY";
    static immutable S empty = "EMPTY";

    static immutable S fixed = "#FIXED";
    static immutable S implied = "#IMPLIED";
    static immutable S required = "#REQUIRED";

    static immutable S nData = "NDATA";

    static immutable S notation = "NOTATION";
    static immutable S public_ = "PUBLIC";
    static immutable S system = "SYSTEM";

    static immutable S xml = "xml";
    static immutable S xmlNS = "http://www.w3.org/XML/1998/namespace";
    static immutable S xmlns = "xmlns";
    static immutable S xmlnsNS = "http://www.w3.org/2000/xmlns/";
    
    static immutable S boolTrue = "true";
    static immutable S boolFalse = "false";
    
    static immutable S floatNaN = "NaN";
    static immutable S floatNInf = "-Infinity";    
    static immutable S floatPInf = "Infinity";
}
