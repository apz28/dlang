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

module pham.xml.xml_xpath;

import std.conv : to;
import std.math : isNaN;
import std.typecons : Flag, No, Yes;

debug(debug_pham_xml_xml_xpath) import std.stdio : writeln;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_enum_set : EnumArray;
import pham.utl.utl_object : singleton;
import pham.utl.utl_text : className, shortClassName;
import pham.xml.xml_buffer;
import pham.xml.xml_dom;
import pham.xml.xml_exception;
import pham.xml.xml_message;
import pham.xml.xml_object;
import pham.xml.xml_type;
import pham.xml.xml_util;
import pham.xml.xml_writer;

@safe:

/** Returns first node of matching xpath expression
    Params:
        source = a context node to search from
        xpath = a xpath expression string
    Returns:
        a node, XmlNode, of matching xpath expression or null if no matching found
*/
XmlNode!S selectSingleNode(S = string)(XmlNode!S source, S xpath)
if (isXmlString!S)
{
    auto resultList = selectNodes(source, xpath);
    return resultList.empty ? null : resultList.front;
}

/** Returns node-list of matching xpath expression
    Params:
        source = a context node to search from
        xpath = a xpath expression string
    Returns:
        a node-list, XmlNodeList, of matching xpath expression
*/
XmlNodeList!S selectNodes(S = string)(XmlNode!S source, S xpath)
if (isXmlString!S)
{
    auto xpathParser = XPathParser!S(xpath);
    auto xpathExpression = xpathParser.parseExpression();

    debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(xpath=", xpath, ") - ", xpathExpression.outerXml());

    auto inputContext = XPathContext!S(source);
    inputContext.resNodes.insertBack(source);

    auto outputContext = inputContext.createOutputContext();
    xpathExpression.evaluate(inputContext, outputContext);

    return outputContext.resNodes;
}

enum XPathAxisType : ubyte
{
    error,
    ancestor,
    ancestorOrSelf,
    attribute,
    child,
    descendant,
    descendantOrSelf,
    following,
    followingSibling,
    namespace,
    parent,
    preceding,
    precedingSibling,
    self,
}

enum XPathAstType : ubyte
{
    error,
    axis,
    constant,
    filter,
    function_,
    group,
    operator,
    root,
    variable,
}

enum XPathCaseOrder : ubyte
{
    none,
    upperFirst,
    lowerFirst,
}

enum XPathDataType : ubyte
{
    empty,
    boolean,
    number,
    text,
}

enum XPathFunctionType : ubyte
{
    boolean,
    ceiling,
    //choose,
    concat,
    contains,
    count,
    //current,
    //document,
    //elementAvailable,
    false_,
    floor,
    //formatNumber,
    //functionAvailable,
    //generateId,
    id,
    //key,
    lang,
    last,
    localName,
    name,
    namespaceUri,
    normalizeSpace,
    not,
    number,
    position,
    round,
    startsWith,
    string,
    stringLength,
    substring,
    substringAfter,
    substringBefore,
    sum,
    //systemProperty,
    //text,
    translate,
    true_,
    //unparsedEntityUrl,
    userDefined,
}

alias FunctionTypeNameTable = EnumArray!(XPathFunctionType, string);
static immutable FunctionTypeNameTable functionTypeNameTable = FunctionTypeNameTable(
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.boolean, "boolean"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.ceiling, "ceiling"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.concat, "concat"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.contains, "contains"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.count, "count"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.false_, "false"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.floor, "floor"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.id, "id"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.lang, "lang"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.last, "last"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.localName, "local-name"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.name, "name"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.namespaceUri, "namespace-uri"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.normalizeSpace, "normalize-space"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.not, "not"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.number, "number"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.position, "position"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.round, "round"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.startsWith, "starts-with"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.string, "string"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.stringLength, "string-length"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.substring, "substring"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.substringAfter, "substring-after"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.substringBefore, "substring-before"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.sum, "sum"),
    //FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.text, "text"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.translate, "translate"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.true_, "true"),
    FunctionTypeNameTable.EnumArrayEntry(XPathFunctionType.userDefined, "?UserDefined?"),
    );

pragma(inline, true)
string functionTypeName(XPathFunctionType functionType, string userDefinedName = null) nothrow pure
{
    return functionType != XPathFunctionType.userDefined
        ? functionTypeNameTable[functionType]
        : userDefinedName;
}

enum XPathNodeType : ubyte
{
    all,
    attribute,
    comment,
    element,
    namespace,
    processingInstruction,
    root,
    significantWhitespace,
    text,
    whitespace,
}

enum XPathOp : ubyte
{
    error,
    // Logical
    and,
    or,
    // Equality
    eq,
    ne,
    // Relational
    lt,
    le,
    gt,
    ge,
    // Arithmetic
    plus,
    minus,
    multiply,
    divide,
    mod,
    // Union
    union_,
}

enum XPathResultType : ubyte
{
    error,
    any,
    boolean,
    nodeSet,
    number,
    text,
}

enum navigator = XPathResultType.text;

enum XPathSortOrder : ubyte
{
    ascending,
    descending,
}

alias FunctionTypeResultTable = EnumArray!(XPathFunctionType, XPathResultType);
static immutable FunctionTypeResultTable functionTypeResultTable = FunctionTypeResultTable(
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.boolean, XPathResultType.boolean),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.ceiling, XPathResultType.number),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.concat, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.contains, XPathResultType.boolean),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.count, XPathResultType.number),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.false_, XPathResultType.boolean),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.floor, XPathResultType.number),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.id, XPathResultType.nodeSet),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.lang, XPathResultType.boolean),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.last, XPathResultType.number),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.localName, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.name, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.namespaceUri, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.normalizeSpace, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.not, XPathResultType.boolean),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.number, XPathResultType.number),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.position, XPathResultType.number),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.round, XPathResultType.number),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.startsWith, XPathResultType.boolean),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.string, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.stringLength, XPathResultType.number),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.substring, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.substringAfter, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.substringBefore, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.sum, XPathResultType.number),
    //FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.text, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.translate, XPathResultType.text),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.true_, XPathResultType.boolean),
    FunctionTypeResultTable.EnumArrayEntry(XPathFunctionType.userDefined, XPathResultType.any),
    );

pragma(inline, true)
XPathResultType functionResultType(XPathFunctionType functionType) nothrow pure
{
    return functionTypeResultTable[functionType];
}

alias InvertedOpTable = EnumArray!(XPathOp, XPathOp);
static immutable InvertedOpTable invertedOpTable = InvertedOpTable(
    InvertedOpTable.EnumArrayEntry(XPathOp.error, XPathOp.error),
    InvertedOpTable.EnumArrayEntry(XPathOp.and, XPathOp.or),
    InvertedOpTable.EnumArrayEntry(XPathOp.or, XPathOp.and),
    InvertedOpTable.EnumArrayEntry(XPathOp.eq, XPathOp.ne),
    InvertedOpTable.EnumArrayEntry(XPathOp.ne, XPathOp.eq),
    InvertedOpTable.EnumArrayEntry(XPathOp.lt, XPathOp.gt),
    InvertedOpTable.EnumArrayEntry(XPathOp.le, XPathOp.ge),
    InvertedOpTable.EnumArrayEntry(XPathOp.gt, XPathOp.lt),
    InvertedOpTable.EnumArrayEntry(XPathOp.ge, XPathOp.le),
    InvertedOpTable.EnumArrayEntry(XPathOp.plus, XPathOp.minus),
    InvertedOpTable.EnumArrayEntry(XPathOp.minus, XPathOp.plus),
    InvertedOpTable.EnumArrayEntry(XPathOp.multiply, XPathOp.divide),
    InvertedOpTable.EnumArrayEntry(XPathOp.divide, XPathOp.multiply),
    InvertedOpTable.EnumArrayEntry(XPathOp.mod, XPathOp.error),
    InvertedOpTable.EnumArrayEntry(XPathOp.union_, XPathOp.error)
    );

pragma(inline, true)
XPathOp invertedOp(XPathOp op) nothrow pure
{
    return invertedOpTable[op];
}

alias ToXmlNodeTypeTable = EnumArray!(XPathNodeType, XmlNodeType);
static immutable ToXmlNodeTypeTable toXmlNodeTypeTable = ToXmlNodeTypeTable(
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.all, XmlNodeType.unknown),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.attribute, XmlNodeType.attribute),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.comment, XmlNodeType.comment),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.element, XmlNodeType.element),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.namespace, XmlNodeType.attribute),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.processingInstruction, XmlNodeType.processingInstruction),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.root, XmlNodeType.document),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.significantWhitespace, XmlNodeType.significantWhitespace),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.text, XmlNodeType.text),
    ToXmlNodeTypeTable.EnumArrayEntry(XPathNodeType.whitespace, XmlNodeType.whitespace)
    );

pragma(inline, true)
XmlNodeType toXmlNodeType(XPathNodeType nodeType) nothrow pure
{
    return toXmlNodeTypeTable[nodeType];
}

struct XPathValue(S = string)
if (isXmlString!S)
{
@safe:

public:
    alias C = XmlChar!S;

public:
    this(bool value) nothrow pure
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        this._type = XPathDataType.boolean;
        this.boolean = value;
    }

    this(double value) nothrow pure
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        this._type = XPathDataType.number;
        this.number = value;
    }

    this(S value) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        this._type = XPathDataType.text;
        this._text = value;
    }

    this(scope const(C)[] value) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        this._type = XPathDataType.text;
        this._text = value.idup;
    }

    this(const typeof(this) source) nothrow @trusted
	{
        //debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        this._type = source.type;
        final switch (source.type)
        {
            case XPathDataType.empty:
                break;
            case XPathDataType.boolean:
                this.boolean = source.boolean;
                break;
            case XPathDataType.number:
                this.number = source.number;
                break;
            case XPathDataType.text:
                this._text = source.text;
                break;
        }
    }

    ~this()
    {
        if (_type != XPathDataType.empty)
            doClear();
    }

    void opAssign(bool value) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        if (_type != XPathDataType.boolean)
            clear();
        this._type = XPathDataType.boolean;
        this.boolean = value;
    }

    void opAssign(double value) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        if (_type != XPathDataType.number)
            clear();
        this._type = XPathDataType.number;
        this.number = value;
    }

    void opAssign(S value) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        if (_type != XPathDataType.text)
            clear();
        this._type = XPathDataType.text;
        this._text = value;
    }

    void opAssign(scope const(C)[] value) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        if (_type != XPathDataType.text)
            clear();
        this._type = XPathDataType.text;
        this._text = value.idup;
    }

    void opAssign(const typeof(this) source) nothrow @trusted
    {
        clear();

        this._type = source.type;
        final switch (source.type)
        {
            case XPathDataType.empty:
                break;
            case XPathDataType.boolean:
                this.boolean = source.boolean;
                break;
            case XPathDataType.number:
                this.number = source.number;
                break;
            case XPathDataType.text:
                this._text = source.text;
                break;
        }
    }

    bool opCast(B: bool)() const nothrow
    {
        final switch (type)
        {
            case XPathDataType.empty:
                return false;
            case XPathDataType.boolean:
                return boolean;
            case XPathDataType.number:
                return number != 0;
            case XPathDataType.text:
                return text.length != 0;
        }
    }

	bool opEquals(const ref typeof(this) other) const nothrow
	{
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(this=", this, ", other=", other, ")");

        return opCmp(other) == 0;
	}

	int opCmp(const ref typeof(this) other) const nothrow @trusted
    {
        import std.math : cmp;
        import std.uni : sicmp;

        int result;
        if (this.type == other.type)
        {
            final switch (type)
            {
                case XPathDataType.empty:
                    result = 0;
                    break;
                case XPathDataType.boolean:
                    result = cast(int)boolean - cast(int)(other.boolean);
                    break;
                case XPathDataType.number:
                    result = cmp(number, other.number);
                    break;
                case XPathDataType.text:
                    result = sicmp(text, other.text);
                    break;
            }
        }
        else if (this.type == XPathDataType.empty || other.type == XPathDataType.empty)
            result = cast(int)XPathDataType.empty - cast(int)other.empty;
        else
            result = sicmp(toString(), other.toString());

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(this=", this, ", other=", other, ", result=", result, ")");

        return result;
    }

    void clear() nothrow
    {
        //debug(debug_pham_xml_xml_xpath) outputXmlTraceXPathParserF("XPathValue.clear(value[%d]: %s)", _type, toString());

        if (_type != XPathDataType.empty)
            doClear();
    }

    private void doClear() nothrow @trusted
    {
        // Do not log or use any codes using string (GC data) since it can be called from destructor
        final switch (_type)
        {
            case XPathDataType.empty:
            case XPathDataType.boolean:
            case XPathDataType.number:
                break;
            case XPathDataType.text:
                _text = null;
                break;
        }
        _type = XPathDataType.empty;
        _dummy[] = 0;
    }

    S toString() const nothrow @trusted
    {
        final switch (_type)
        {
            case XPathDataType.empty:
                return null;
            case XPathDataType.boolean:
                return toText!S(boolean);
            case XPathDataType.number:
                return toText!S(number);
            case XPathDataType.text:
                return text;
        }
    }

    @property bool empty() const nothrow
    {
        return _type == XPathDataType.empty;
    }

    @property XPathResultType resultType() const nothrow
    {
        final switch (_type)
        {
            case XPathDataType.boolean:
                return XPathResultType.boolean;
            case XPathDataType.number:
                return XPathResultType.number;
            case XPathDataType.empty:
            case XPathDataType.text:
                return XPathResultType.text;
        }
    }

    @property S text() const nothrow @trusted
    in
    {
        assert(_type == XPathDataType.empty || _type == XPathDataType.text);
    }
    do
    {
        return _type == XPathDataType.text ? _text : null;
    }

    pragma(inline, true)
    @property XPathDataType type() const nothrow
    {
        return _type;
    }

    union
    {
        size_t[2] _dummy; // First member to be initialized to all zero
        double number;    // 8 bytes
        S _text;          // 8 or 16 bytes depending on pointer
        bool boolean;     // 1 byte
    }

private:
    XPathDataType _type;
}

struct XPathContext(S = string)
if (isXmlString!S)
{
@safe:

public:
    alias C = XmlChar!S;

public:
    @disable this(this);
    @disable void opAssign(typeof(this));

    this(XmlNode!S xpathNode) nothrow pure
    {
        debug(debug_pham_xml_xml_xpath) nodeIndent = &_nodeIndent;

        this._xpathNode = xpathNode;
        this.resNodes = XmlNodeList!S(null);
    }

    void clear() nothrow
    {
        if (!resNodes.empty)
            resNodes = XmlNodeList!S(null);
        resValue.clear();
    }

    XPathContext!S createOutputContext() nothrow
    {
        auto result = XPathContext!S(_xpathNode);
        result.variables = variables;
        result.filterNodes = filterNodes;
        return result;
    }

    XmlDocument!S xpathDocument() nothrow
    {
        return xpathNode.document();
    }

    @property bool hasResNodes() nothrow
    {
        return !resNodes.empty;
    }

    @property bool hasResValue() const nothrow
    {
        return !resValue.empty;
    }

    @property XmlNode!S xpathNode() nothrow
    {
        return _xpathNode;
    }

    @property XmlElement!S xpathDocumentElement() nothrow
    {
        if (_xpathDocumentElement is null)
            _xpathDocumentElement = xpathDocument().documentElement();
        return _xpathDocumentElement;
    }

package:
    debug(debug_pham_xml_xml_xpath)
    {
        void decNodeIndent()
        {
            *nodeIndent -= 1;
        }

        void incNodeIndent()
        {
            *nodeIndent += 1;
        }

        string indentString()
        {
            return stringOfChar!string(' ', (*nodeIndent) << 1);
        }
    }

public:
    XmlNodeList!S resNodes;
    XPathValue!S resValue;

    XmlNodeList!S filterNodes;
    Dictionary!(S, XPathValue!S) variables;

package:
    debug(debug_pham_xml_xml_xpath)
    {
        static size_t _nodeIndent;
        size_t* nodeIndent;
    }

private:
    XmlNode!S _xpathNode;
    XmlElement!S _xpathDocumentElement;
}

abstract class XPathNode(S = string) : XmlObject!S
{
@safe:

public:
    abstract void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext);
    
    T get(T)(ref XPathContext!S inputContext)
    if (is(T == S) || is(T == double) || is(T == bool) || is(T == const(C)[]))
    {
        auto tempOutputContext = inputContext.createOutputContext();
        evaluate(inputContext, tempOutputContext);

        if (tempOutputContext.hasResValue)
        {
            static if (is(T == bool))
                return normalizeValueToBoolean!S(tempOutputContext.resValue);
            else static if (is(T == double))
                return normalizeValueToNumber!S(tempOutputContext.resValue);
            else
                return normalizeValueToText!S(tempOutputContext.resValue);
        }
        else
        {
            static if (is(T == bool))
                return (!tempOutputContext.resNodes.empty);
            else static if (is(T == double))
            {
                if (tempOutputContext.resNodes.empty)
                    return double.nan;
                else
                    return toNumber!S(tempOutputContext.resNodes.front.toText());
            }
            else
            {
                if (tempOutputContext.resNodes.empty)
                    return null;
                else
                    return tempOutputContext.resNodes.front.toText();
            }
        }
    }

    final S outerXml(Flag!"prettyOutput" prettyOutput = No.prettyOutput)
    {
        auto buffer = new XmlBuffer!(S, No.CheckEncoded)();
        write(new XmlStringWriter!S(prettyOutput, buffer));
        return buffer.value();
    }

    final S qualifiedName() nothrow
    {
        if (_qualifiedName.ptr is null)
            _qualifiedName = combineName!S(_prefix, _localName);
        return _qualifiedName;
    }

    abstract XmlWriter!S write(XmlWriter!S writer);

    @property final XPathNode!S parent() nothrow
    {
        return _parent;
    }

    @property abstract XPathAstType astType() const nothrow;
    @property abstract XPathResultType returnType() const nothrow;

protected:
    alias XPathAstNodeEvaluate = void delegate(ref XPathContext!S inputContext, ref XPathContext!S outputContext);

protected:
    final void evaluateError(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), "evaluate()");
    }

protected:
    S _localName;
    S _prefix;
    S _qualifiedName;
    XPathNode!S _parent;
}

class XPathAxis(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent, XPathAxisType axisType, XPathNode!S input,
         XPathNodeType nodetype, S prefix, S localName) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(axisType=", axisType,
            ", nodetype=", nodetype, ", prefix=", prefix, ", localName=", localName);

        this._parent = parent;
        this._input = input;
        this._axisType = axisType;
        this._axisNodeType = nodetype;
        this._prefix = prefix;
        this._localName = localName;

        _xmlMatchAnyName = localName == "*";
        _xmlNodeType = toXmlNodeType(nodetype);
        final switch (axisType)
        {
            case XPathAxisType.error:
                evaluateFct = &evaluateError;
                break;
            case XPathAxisType.ancestor:
                evaluateFct = &evaluateAncestor;
                break;
            case XPathAxisType.ancestorOrSelf:
                evaluateFct = &evaluateAncestorOrSelf;
                break;
            case XPathAxisType.attribute:
                evaluateFct = &evaluateAttribute;
                break;
            case XPathAxisType.child:
                evaluateFct = &evaluateChild;
                break;
            case XPathAxisType.descendant:
                evaluateFct = &evaluateDescendant;
                break;
            case XPathAxisType.descendantOrSelf:
                evaluateFct = &evaluateDescendantOrSelf;
                break;
            case XPathAxisType.following:
                evaluateFct = &evaluateFollowing;
                break;
            case XPathAxisType.followingSibling:
                evaluateFct = &evaluateFollowingSibling;
                break;
            case XPathAxisType.namespace:
                evaluateFct = &evaluateNamespace;
                break;
            case XPathAxisType.parent:
                evaluateFct = &evaluateParent;
                break;
            case XPathAxisType.preceding:
                evaluateFct = &evaluatePreceding;
                break;
            case XPathAxisType.precedingSibling:
                evaluateFct = &evaluatePrecedingSibling;
                break;
            case XPathAxisType.self:
                evaluateFct = &evaluateSelf;
                break;
        }
    }

    this(XPathNode!S parent, XPathAxisType axisType, XPathNode!S input) nothrow
    {
        //debug(debug_pham_xml_xml_xpath) outputXmlTraceXPathParserF("%s.this(axisType: %s, input: %s)", shortClassName(this), axisType, shortClassName(input));

        this(parent, axisType, input, XPathNodeType.all, null, null);
        this._abbreviated = true;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath) { debug writeln(__FUNCTION__, "()");
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        if (input !is null)
        {
            XPathContext!S inputContextCond = inputContext.createOutputContext();
            input.evaluate(inputContext, inputContextCond);

            evaluateFct(inputContextCond, outputContext);
        }
        else
            evaluateFct(inputContext, outputContext);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        import std.format : format;

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        string n = format("::name(axisType=%s, nodeType=%s, abbreviated=%s)", axisType, nodeType, abbreviated);
        writer.putIndent();
        writer.put(toUTF!(string, S)(className(this)));
        writer.putAttribute(toUTF!(string, S)(n), qualifiedName());

        if (input !is null)
        {
            writer.incNodeLevel();
            input.write(writer.putLF());
            writer.decNodeLevel();
        }

        return writer;
    }

    @property final bool abbreviated() const nothrow
    {
        return _abbreviated;
    }

    @property final override XPathAstType astType() const nothrow
    {
        return XPathAstType.axis;
    }

    @property final XPathAxisType axisType() const nothrow
    {
        return _axisType;
    }

    @property final XPathNode!S input() nothrow
    {
        return _input;
    }

    @property final S localName() const nothrow
    {
        return _localName;
    }

    @property final S prefix() const nothrow
    {
        return _prefix;
    }

    @property final XPathNodeType nodeType() const nothrow
    {
        return _axisNodeType;
    }

    @property final override XPathResultType returnType() const nothrow
    {
        return XPathResultType.nodeSet;
    }

protected:
    final bool accept(XmlNode!S node) nothrow
    {
        // XmlNodeType.unknown = all
        bool result = (_xmlNodeType == XmlNodeType.unknown || node.nodeType == _xmlNodeType);

        if (!_xmlMatchAnyName)
        {
            const equalName = node.document.equalName;
            if (result && prefix.length != 0)
                result = equalName(node.prefix, prefix);
            if (result && localName.length != 0)
                result = equalName(node.localName, localName);
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(node.name=", node.name, ", result=", result, ")");

        return result;
    }

    final void evaluateAncestor(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            auto p = e.parent;
            while (p !is null)
            {
                if (accept(p))
                    outputContext.resNodes.insertBack(p);
                p = p.parent;
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateAncestorOrSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (accept(e))
                outputContext.resNodes.insertBack(e);

            auto p = e.parent;
            while (p !is null)
            {
                if (accept(p))
                    outputContext.resNodes.insertBack(p);
                p = p.parent;
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateAttribute(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.element && e.hasAttributes)
            {
                auto attributes = e.attributes;
                foreach (a; attributes)
                {
                    if (accept(a))
                        outputContext.resNodes.insertBack(a);
                }
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateChild(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (!e.hasChildNodes)
                continue;

            auto childNodes = e.childNodes;
            foreach (e2; childNodes)
            {
                if (accept(e2))
                    outputContext.resNodes.insertBack(e2);
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateDescendant(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            auto childNodes = e.getChildNodes(null, Yes.deep);
            foreach (e2; childNodes)
            {
                if (accept(e2))
                    outputContext.resNodes.insertBack(e2);
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateDescendantOrSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType != XmlNodeType.attribute && accept(e))
                outputContext.resNodes.insertBack(e);

            auto childNodes = e.getChildNodes(null, Yes.deep);
            foreach (e2; childNodes)
            {
                if (accept(e2))
                    outputContext.resNodes.insertBack(e2);
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateFollowing(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.nextSibling;
            if (n !is null && accept(n))
                outputContext.resNodes.insertBack(n);
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateFollowingSibling(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.nextSibling;
            while (n !is null)
            {
                if (accept(n))
                    outputContext.resNodes.insertBack(n);
                n = n.nextSibling;
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateNamespace(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType != XmlNodeType.element || !e.hasAttributes)
                continue;

            XmlNodeList!S attributes = e.attributes;
            foreach (a; attributes)
            {
                if (accept(a))
                    outputContext.resNodes.insertBack(a);
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateParent(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            auto p = e.parent;
            if (p !is null && accept(p))
                outputContext.resNodes.insertBack(p);
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluatePreceding(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.previousSibling;
            if (n !is null && accept(n))
                outputContext.resNodes.insertBack(n);
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluatePrecedingSibling(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.previousSibling;
            while (n !is null)
            {
                if (accept(n))
                    outputContext.resNodes.insertBack(n);
                n = n.previousSibling;
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

    final void evaluateSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        foreach (e; inputContext.resNodes)
        {
            if (accept(e))
                outputContext.resNodes.insertBack(e);
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - inputContext=", inputContext.indentString, ", outputContext.resNodes.length=", outputContext.resNodes.length);
    }

protected:
    XPathAstNodeEvaluate evaluateFct;
    XPathNode!S _input;
    XPathAxisType _axisType;
    XPathNodeType _axisNodeType;
    XmlNodeType _xmlNodeType;
    bool _abbreviated, _xmlMatchAnyName;
}

class XPathFilter(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent, XPathNode!S input, XPathNode!S condition) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        this._parent = parent;
        this._input = input;
        this._condition = condition;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", inputContext.indentString);
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        auto inputContextEval = inputContext.createOutputContext();
        input.evaluate(inputContext, inputContextEval);

        if (!inputContextEval.resNodes.empty)
        {
            auto outputContextCond = inputContextEval.createOutputContext();
            auto inputContextCond = inputContextEval.createOutputContext();
            inputContextCond.filterNodes = inputContextEval.resNodes;

            for (size_t i = 0; i < inputContextEval.resNodes.length; ++i)
            {
                auto e = inputContextEval.resNodes.item(i);

                inputContextCond.clear();
                inputContextCond.resNodes.insertBack(e);

                outputContextCond.clear();
                condition.evaluate(inputContextCond, outputContextCond);

                if (!outputContextCond.resValue.empty)
                {
                    auto v = outputContextCond.resValue;
                    if (normalizeValueToBoolean!S(v))
                        outputContext.resNodes.insertBack(e);
                }
            }
        }
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        writer.putIndent();
        writer.put(toUTF!(string, S)(className(this)));
        writer.incNodeLevel();
        input.write(writer.putLF());
        condition.write(writer.putLF());
        writer.decNodeLevel();

        return writer;
    }

    @property final override XPathAstType astType() const nothrow
    {
        return XPathAstType.filter;
    }

    @property final XPathNode!S condition() nothrow
    {
        return _condition;
    }

    @property final XPathNode!S input() nothrow
    {
        return _input;
    }

    @property final override XPathResultType returnType() const nothrow
    {
        return XPathResultType.nodeSet;
    }

protected:
    XPathNode!S _input, _condition;
}

class XPathUserDefinedFunctionEntry(S = string) : XmlObject!S
{
@safe:

public:
    this(S prefix, S localName, XPathResultType resultType,
        XPathFunctionTable!S.XPathFunctionEvaluate evaluate) nothrow
    {
        this._prefix = prefix;
        this._localName = localName;
        this._resultType = resultType;
        this._evaluate = evaluate;

        _qualifiedName = combineName!S(_prefix, _localName);
    }

    @property final XPathFunctionTable!S.XPathFunctionEvaluate evaluate() const nothrow
    {
        return _evaluate;
    }

    @property final S localName() const nothrow
    {
        return _localName;
    }

    @property final S prefix() const nothrow
    {
        return _prefix;
    }

    @property final S qualifiedName() const nothrow
    {
        return _qualifiedName;
    }

    @property final XPathResultType returnType() const nothrow
    {
        return _resultType;
    }

private:
    S _localName;
    S _prefix;
    S _qualifiedName;
    XPathFunctionTable!S.XPathFunctionEvaluate _evaluate;
    XPathResultType _resultType;
}

class XPathFunctionTable(S = string) : XmlObject!S
{
@safe:

public:
    alias XPathFunctionEvaluate = void function(XPathFunction!S context,
        ref XPathContext!S inputContext, ref XPathContext!S outputContext);

public:
    this() nothrow pure
    {
        initDefault();
    }

    static XPathFunctionTable!S defaultFunctionTable() nothrow @trusted
    {
        return singleton!(XPathFunctionTable!S)(_defaultFunctionTable, &createDefaultFunctionTable);
    }

    final bool find(scope const(C)[] name, ref XPathUserDefinedFunctionEntry!S fct) const nothrow @trusted
    {
        const(XPathUserDefinedFunctionEntry!S)* r = name in userDefinedFunctions;

        if (r is null)
            return false;
        else
        {
            fct = cast(XPathUserDefinedFunctionEntry!S)* r;
            return true;
        }
    }

    final bool find(scope const(C)[] name, ref XPathFunctionEvaluate fct) const nothrow
    {
        const(XPathFunctionEvaluate)* r = name in defaultFunctions;

        if (r is null)
        {
            XPathUserDefinedFunctionEntry!S u;
            if (find(name, u))
            {
                fct = u.evaluate;
                return true;
            }
            else
                return false;
        }
        else
        {
            fct = *r;
            return true;
        }
    }

public:
    Dictionary!(S, XPathUserDefinedFunctionEntry!S) userDefinedFunctions;

protected:
    static XPathFunctionTable!S createDefaultFunctionTable() nothrow pure
    {
        return new XPathFunctionTable!S();
    }

    final void initDefault() nothrow pure
    {
        defaultFunctions.reserve(35, 30);
        defaultFunctions[functionTypeName(XPathFunctionType.boolean)] = &fctBoolean!S;
        defaultFunctions[functionTypeName(XPathFunctionType.ceiling)] = &fctCeiling!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.choose)] = &fctChoose!S;
        defaultFunctions[functionTypeName(XPathFunctionType.concat)] = &fctConcat!S;
        defaultFunctions[functionTypeName(XPathFunctionType.contains)] = &fctContains!S;
        defaultFunctions[functionTypeName(XPathFunctionType.count)] = &fctCount!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.current)] = &fctCurrent!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.document)] = &fctDocument!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.element-available)] = &fctElementAvailable!S;
        defaultFunctions[functionTypeName(XPathFunctionType.false_)] = &fctFalse!S;
        defaultFunctions[functionTypeName(XPathFunctionType.floor)] = &fctFloor!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.formatNumber)] = &fctFormatNumber!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.functionAvailable)] = &fctFunctionAvailable!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.generateId)] = &fctGenerateId!S;
        defaultFunctions[functionTypeName(XPathFunctionType.id)] = &fctId!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.key)] = &fctKey!S;
        defaultFunctions[functionTypeName(XPathFunctionType.lang)] = &fctLang!S;
        defaultFunctions[functionTypeName(XPathFunctionType.last)] = &fctLast!S;
        defaultFunctions[functionTypeName(XPathFunctionType.localName)] = &fctLocalName!S;
        defaultFunctions[functionTypeName(XPathFunctionType.name)] = &fctName!S;
        defaultFunctions[functionTypeName(XPathFunctionType.namespaceUri)] = &fctNamespaceUri!S;
        defaultFunctions[functionTypeName(XPathFunctionType.normalizeSpace)] = &fctNormalizeSpace!S;
        defaultFunctions[functionTypeName(XPathFunctionType.not)] = &fctNot!S;
        defaultFunctions[functionTypeName(XPathFunctionType.number)] = &fctNumber!S;
        defaultFunctions[functionTypeName(XPathFunctionType.position)] = &fctPosition!S;
        defaultFunctions[functionTypeName(XPathFunctionType.round)] = &fctRound!S;
        defaultFunctions[functionTypeName(XPathFunctionType.startsWith)] = &fctStartsWith!S;
        defaultFunctions[functionTypeName(XPathFunctionType.string)] = &fctString!S;
        defaultFunctions[functionTypeName(XPathFunctionType.stringLength)] = &fctStringLength!S;
        defaultFunctions[functionTypeName(XPathFunctionType.substring)] = &fctSubstring!S;
        defaultFunctions[functionTypeName(XPathFunctionType.substringAfter)] = &fctSubstringAfter!S;
        defaultFunctions[functionTypeName(XPathFunctionType.substringBefore)] = &fctSubstringBefore!S;
        defaultFunctions[functionTypeName(XPathFunctionType.sum)] = &fctSum!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.systemProperty)] = &fctSystemProperty!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.text)] = &fctText!S;
        defaultFunctions[functionTypeName(XPathFunctionType.translate)] = &fctTranslate!S;
        defaultFunctions[functionTypeName(XPathFunctionType.true_)] = &fctTrue!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.unparsedEntityUrl)] = &fctUnparsedEntityUrl!S;
        //defaultFunctions[functionTypeName(XPathFunctionType.)] = &fct!S;
    }

protected:
    Dictionary!(S, XPathFunctionEvaluate) defaultFunctions;

private:
    __gshared static XPathFunctionTable!S _defaultFunctionTable;
}

class XPathFunction(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent, XPathFunctionType functionType, XPathNode!S[] argumentList)
    in
    {
        assert(functionType != XPathFunctionType.userDefined);
    }
    do
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(functionType=", functionType, ")");

        this._parent = parent;
        this._functionType = functionType;
        this._argumentList = argumentList; //argumentList.dup();

        setEvaluateFct();
    }

    this(XPathNode!S parent, S prefix, S localName, XPathNode!S[] argumentList)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(prefix=", prefix, ", localName=", localName, ")");

        this._parent = parent;
        this._functionType = XPathFunctionType.userDefined;
        this._prefix = prefix;
        this._localName = localName;
        this._argumentList = argumentList; //argumentList.dup;

        setEvaluateFct();
    }

    this(XPathNode!S parent, XPathFunctionType functionType)
    in
    {
        assert(functionType != XPathFunctionType.userDefined);
    }
    do
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(functionType=", functionType, ")");

        this._parent = parent;
        this._functionType = functionType;

        setEvaluateFct();
    }

    this(XPathNode!S parent, XPathFunctionType functionType, XPathNode!S argument)
    in
    {
        assert(functionType != XPathFunctionType.userDefined);
    }
    do
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(functionType=", functionType, ")");

        this._parent = parent;
        this._functionType = functionType;
        this._argumentList ~= argument;

        setEvaluateFct();
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "()");
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        return evaluateFct(this, inputContext, outputContext);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        import std.format : format;

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        string n = format("::name(%s:%s)", functionType, returnType);
        writer.putIndent();
        writer.put(toUTF!(string, S)(className(this)));
        writer.putAttribute(toUTF!(string, S)(n), qualifiedName());

        if (argumentList.length != 0)
        {
            writer.incNodeLevel();
            foreach (e; argumentList)
                e.write(writer.putLF());
            writer.decNodeLevel();
        }

        return writer;
    }

    @property final XPathNode!S[] argumentList() nothrow
    {
        return _argumentList;
    }

    @property final override XPathAstType astType() const nothrow
    {
        return XPathAstType.function_;
    }

    @property final XPathFunctionType functionType() const nothrow
    {
        return _functionType;
    }

    @property final S localName() const nothrow
    {
        return _localName;
    }

    @property final S prefix() const nothrow
    {
        return _prefix;
    }

    @property final override XPathResultType returnType() const nothrow
    {
        if (functionType == XPathFunctionType.userDefined)
            return userDefinedevaluateFct.returnType;
        else
            return functionResultType(functionType);
    }

protected:
    final void setEvaluateFct()
    {
        if (functionType != XPathFunctionType.userDefined)
        {
            const functionName = functionTypeName(functionType);
            XPathFunctionTable!S.defaultFunctionTable().find(functionName, evaluateFct);

            if (evaluateFct is null)
                throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), functionName);
        }
        else
        {
            XPathFunctionTable!S.defaultFunctionTable().find(qualifiedName(), userDefinedevaluateFct);
            if (userDefinedevaluateFct is null && prefix.length != 0)
                XPathFunctionTable!S.defaultFunctionTable().find(localName, userDefinedevaluateFct);

            if (userDefinedevaluateFct is null)
                throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), qualifiedName());

            evaluateFct = userDefinedevaluateFct.evaluate;
        }
    }

protected:
    XPathUserDefinedFunctionEntry!S userDefinedevaluateFct;
    XPathFunctionTable!S.XPathFunctionEvaluate evaluateFct;
    XPathNode!S[] _argumentList;
    XPathFunctionType _functionType;
}

class XPathGroup(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent, XPathNode!S groupNode) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        this._parent = parent;
        this._groupNode = groupNode;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "()");
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), "evaluate()");

        // TODO Implementation
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        writer.putIndent();
        writer.put(toUTF!(string, S)(className(this)));
        writer.incNodeLevel();
        groupNode.write(writer.putLF());
        writer.decNodeLevel();

        return writer;
    }

    @property final override XPathAstType astType() const nothrow
    {
        return XPathAstType.group;
    }

    @property final XPathNode!S groupNode() nothrow
    {
        return _groupNode;
    }

    @property final override XPathResultType returnType() const nothrow
    {
        return XPathResultType.nodeSet;
    }

protected:
    XPathNode!S _groupNode;
}

class XPathOperand(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent, bool value) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        this._parent = parent;
        this._value = value;
    }

    this(XPathNode!S parent, double value) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        this._parent = parent;
        this._value = value;
    }

    this(XPathNode!S parent, S value) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

        this._parent = parent;
        this._value = value;
    }

    T get(T)(ref XPathContext!S inputContext)
    if (is(T == S) || is(T == double) || is(T == bool))
    {
        static if (is(T == bool))
        {
            final switch (_value.dataType)
            {
                case XPathDataType.boolean:
                    return _value.boolean;
                case XPathDataType.number:
                    return toBoolean(_value.number);
                case XPathDataType.text:
                    return _value.text.length != 0;
            }
        }
        else static if (is(T == double))
        {
            final switch (_value.dataType)
            {
                case XPathDataType.boolean:
                    return toNumber(_value.boolean);
                case XPathDataType.number:
                    return _value.number;
                case XPathDataType.text:
                    return toNumber!S(_value.text);
            }
        }
        else
        {
            final switch (_value.dataType)
            {
                case XPathDataType.boolean:
                    return toText!S(_value.boolean);
                case XPathDataType.number:
                    return toText!S(_value.number);
                case XPathDataType.text:
                    return _value.text;
            }
        }
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - ", inputContext.indentString);

        outputContext.resValue = value;
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        import std.format : format;

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        string n = format("::value(%s)", returnType);
        writer.putIndent();
        writer.put(toUTF!(string, S)(className(this)));
        writer.putAttribute(toUTF!(string, S)(n), toUTF!(string, S)(value.toString()));

        return writer;
    }

    @property final override XPathAstType astType() const nothrow
    {
        return XPathAstType.constant;
    }

    @property final override XPathResultType returnType() const nothrow
    {
        return _value.resultType;
    }

    @property final XPathValue!S value() nothrow
    {
        return _value;
    }

protected:
    XPathValue!S _value;
}

class XPathOperator(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent, XPathOp opType, XPathNode!S operand1, XPathNode!S operand2) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(opType=", opType, ")");

        this._parent = parent;
        this._opType = opType;
        this._operand1 = operand1;
        this._operand2 = operand2;

        setEvaluateFct();
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", inputContext.indentString);
            inputContext.incNodeIndent;
            scope (exit)
                inputContext.decNodeIndent;
        }

        return evaluateFct(inputContext, outputContext);
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        writer.putIndent();
        writer.put(toUTF!(string, S)(className(this)));
        writer.putAttribute("::opType", opType.to!S());
        writer.incNodeLevel();
        operand1.write(writer.putLF());
        operand2.write(writer.putLF());
        writer.decNodeLevel();

        return writer;
    }

    @property final override XPathAstType astType() const nothrow
    {
        return XPathAstType.operator;
    }

    @property final XPathNode!S operand1() nothrow
    {
        return _operand1;
    }

    @property final XPathNode!S operand2() nothrow
    {
        return _operand2;
    }

    @property final XPathOp opType() const nothrow
    {
        return _opType;
    }

    @property final override XPathResultType returnType() const nothrow
    {
        if (opType == XPathOp.error)
            return XPathResultType.error;
        else if (opType <= XPathOp.ge)
            return XPathResultType.boolean;
        else if (opType <= XPathOp.mod)
            return XPathResultType.number;
        else
            return XPathResultType.nodeSet;
    }

protected:
    final void evaluateAnd(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        bool result = operand1.get!bool(inputContext);
        if (result)
            result = operand2.get!bool(inputContext);

        outputContext.resValue = result;
    }

    final void evaluateDivide(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("/", S)(this, inputContext, outputContext);
    }

    final void evaluateEq(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!("==", S)(this, inputContext, outputContext);
    }

    final void evaluateGe(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!(">=", S)(this, inputContext, outputContext);
    }

    final void evaluateGt(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!(">", S)(this, inputContext, outputContext);
    }

    final void evaluateLe(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!("<=", S)(this, inputContext, outputContext);
    }

    final void evaluateLt(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!("<", S)(this, inputContext, outputContext);
    }

    final void evaluateMinus(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("-", S)(this, inputContext, outputContext);
    }

    final void evaluateMod(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("mod", S)(this, inputContext, outputContext);
    }

    final void evaluateMultiply(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("*", S)(this, inputContext, outputContext);
    }

    final void evaluateNe(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opCompare!("!=", S)(this, inputContext, outputContext);
    }

    final void evaluateOr(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        bool result = operand1.get!bool(inputContext);
        if (!result)
            result = operand2.get!bool(inputContext);

        outputContext.resValue = result;
    }

    final void evaluatePlus(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        opBinary!("+", S)(this, inputContext, outputContext);
    }

    final void evaluateUnion(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto tempOutputContext1 = inputContext.createOutputContext();
        operand1.evaluate(inputContext, tempOutputContext1);
        for (size_t i = 0; i < tempOutputContext1.resNodes.length; ++i)
        {
            auto e = tempOutputContext1.resNodes.item(i);
            outputContext.resNodes.insertBack(e);
        }

        auto tempOutputContext2 = inputContext.createOutputContext();
        operand2.evaluate(inputContext, tempOutputContext2);
        for (size_t i = 0; i < tempOutputContext2.resNodes.length; ++i)
        {
            auto e = tempOutputContext2.resNodes.item(i);
            outputContext.resNodes.insertBack(e);
        }
    }

    final void setEvaluateFct() nothrow
    {
        final switch (opType)
        {
            case XPathOp.error:
                evaluateFct = &evaluateError;
                break;
            case XPathOp.and:
                evaluateFct = &evaluateAnd;
                break;
            case XPathOp.or:
                evaluateFct = &evaluateOr;
                break;
            case XPathOp.eq:
                evaluateFct = &evaluateEq;
                break;
            case XPathOp.ne:
                evaluateFct = &evaluateNe;
                break;
            case XPathOp.lt:
                evaluateFct = &evaluateLt;
                break;
            case XPathOp.le:
                evaluateFct = &evaluateLe;
                break;
            case XPathOp.gt:
                evaluateFct = &evaluateGt;
                break;
            case XPathOp.ge:
                evaluateFct = &evaluateGe;
                break;
            case XPathOp.plus:
                evaluateFct = &evaluatePlus;
                break;
            case XPathOp.minus:
                evaluateFct = &evaluateMinus;
                break;
            case XPathOp.multiply:
                evaluateFct = &evaluateMultiply;
                break;
            case XPathOp.divide:
                evaluateFct = &evaluateDivide;
                break;
            case XPathOp.mod:
                evaluateFct = &evaluateMod;
                break;
            case XPathOp.union_:
                evaluateFct = &evaluateUnion;
                break;
        }
    }

protected:
    XPathAstNodeEvaluate evaluateFct;
    XPathNode!S _operand1, _operand2;
    XPathOp _opType;
}

class XPathRoot(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent) nothrow
    {
        //debug(debug_pham_xml_xml_xpath) outputXmlTraceXPathParser(shortClassName(this), ".this()");

        this._parent = parent;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - ", inputContext.indentString);

        outputContext.resNodes.insertBack(inputContext.xpathDocumentElement());
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        writer.putIndent();
        writer.put(toUTF!(string, S)(className(this)));

        return writer;
    }

    @property final override XPathAstType astType() const nothrow
    {
        return XPathAstType.root;
    }

    @property final override XPathResultType returnType() const nothrow
    {
        return XPathResultType.nodeSet;
    }
}

class XPathVariable(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent, S prefix, S localName) nothrow
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(prefix=", prefix, ", localName=", localName, ")");

        this._parent = parent;
        this._prefix = prefix;
        this._localName = localName;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - ", inputContext.indentString);

        XPathValue!S* result = qualifiedName() in inputContext.variables;
        if (result is null && prefix.length != 0)
            result = localName in inputContext.variables;

        if (result is null)
            throw new XmlInvalidOperationException(XmlMessage.eInvalidVariableName, qualifiedName());

        outputContext.resValue = *result;
    }

    final override XmlWriter!S write(XmlWriter!S writer)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "()");

        writer.putIndent();
        writer.put(toUTF!(string, S)(className(this)));
        writer.putAttribute("::name", qualifiedName);

        return writer;
    }

    @property final override XPathAstType astType() const nothrow
    {
        return XPathAstType.variable;
    }

    @property final S localName() const nothrow
    {
        return _localName;
    }

    @property final S prefix() const nothrow
    {
        return _prefix;
    }

    @property final override XPathResultType returnType() const nothrow
    {
        return XPathResultType.any;
    }
}

class XPathAxisTypeTable(S = string) : XmlObject!S
{
@safe:

public:
    this() nothrow
    {
        initDefault();
    }

    static XPathAxisTypeTable!S defaultAxisTypeTable() nothrow @trusted
    {
        return singleton!(XPathAxisTypeTable!S)(_defaultAxisTypeTable, &createDefaultAxisTypeTable);
    }

    final XPathAxisType get(scope const(C)[] name, XPathAxisType defaultValue = XPathAxisType.error) const nothrow
    {
        const(XPathAxisType)* r = name in data;

        if (r is null)
            return defaultValue;
        else
            return *r;
    }

public:
    Dictionary!(S, XPathAxisType) data;

protected:
    static XPathAxisTypeTable!S createDefaultAxisTypeTable() nothrow
    {
        return new XPathAxisTypeTable!S();
    }

    final void initDefault() nothrow
    {
        data.reserve(20, 15);
        data["ancestor"] = XPathAxisType.ancestor;
        data["ancestor-or-self"] = XPathAxisType.ancestorOrSelf;
        data["attribute"] = XPathAxisType.attribute;
        data["child"] = XPathAxisType.child;
        data["descendant"] = XPathAxisType.descendant;
        data["descendant-or-self"] = XPathAxisType.descendantOrSelf;
        data["following"] = XPathAxisType.following;
        data["following-sibling"] = XPathAxisType.followingSibling;
        data["namespace"] = XPathAxisType.namespace;
        data["parent"] = XPathAxisType.parent;
        data["preceding"] = XPathAxisType.preceding;
        data["preceding-sibling"] = XPathAxisType.precedingSibling;
        data["self"] = XPathAxisType.self;
    }

private:
    __gshared static XPathAxisTypeTable!S _defaultAxisTypeTable;
}

class XPathParamInfo(S = string) : XmlObject!S
{
@safe:

public:
    this(XPathFunctionType functionType, size_t minArgs, size_t maxArgs,
        const(XPathResultType[]) argTypes) nothrow
    {
        this._functionType = functionType;
        this._minArgs = minArgs;
        this._maxArgs = maxArgs;
        this._argTypes = argTypes;
    }

    @property final const(XPathResultType[]) argTypes() const nothrow
    {
        return _argTypes;
    }

    @property final XPathFunctionType functionType() const nothrow
    {
        return _functionType;
    }

    @property final size_t maxArgs() const nothrow
    {
        return _maxArgs;
    }

    @property final size_t minArgs() const nothrow
    {
        return _minArgs;
    }

    @property final XPathResultType returnType() const nothrow
    {
        return functionResultType(_functionType);
    }

private:
    const(XPathResultType[]) _argTypes;
    size_t _minArgs, _maxArgs;
    XPathFunctionType _functionType;
}

class XPathFunctionParamInfoTable(S = string) : XmlObject!S
{
@safe:

public:
    this() nothrow
    {
        this.data = initDefault();
    }

    static XPathFunctionParamInfoTable!S defaultFunctionParamInfoTable() nothrow @trusted
    {
        return singleton!(XPathFunctionParamInfoTable!S)(_defaultFunctionParamInfoTable, &createDefaultFunctionParamInfoTable);
    }

    final const(XPathParamInfo!S) find(scope const(C)[] name) nothrow
    {
        if (auto e = name in data)
            return *e;
        else
            return null;
    }

public:
    Dictionary!(S, XPathParamInfo!S) data;

protected:
    static XPathFunctionParamInfoTable!S createDefaultFunctionParamInfoTable() nothrow
    {
        return new XPathFunctionParamInfoTable!S();
    }

    static Dictionary!(S, XPathParamInfo!S) initDefault() nothrow
    {
        static immutable XPathResultType[] paramTypeEmpty = [];
        static immutable XPathResultType[] paramType1Any = [XPathResultType.any];
        static immutable XPathResultType[] paramType1Boolean = [XPathResultType.boolean];
        static immutable XPathResultType[] paramType1NodeSet = [XPathResultType.nodeSet];
        static immutable XPathResultType[] paramType1Number = [XPathResultType.number];
        static immutable XPathResultType[] paramType1Text = [XPathResultType.text];
        static immutable XPathResultType[] paramType1Text2Number = [XPathResultType.text, XPathResultType.number, XPathResultType.number];
        static immutable XPathResultType[] paramType2Text = [XPathResultType.text, XPathResultType.text];
        static immutable XPathResultType[] paramType3Text = [XPathResultType.text, XPathResultType.text, XPathResultType.text];

        auto result = Dictionary!(S, XPathParamInfo!S)(50, 30);

        result[functionTypeName(XPathFunctionType.boolean)] = new XPathParamInfo!S(XPathFunctionType.boolean, 1, 1, paramType1Any);
        result[functionTypeName(XPathFunctionType.ceiling)] = new XPathParamInfo!S(XPathFunctionType.ceiling, 1, 1, paramType1Number);
        result[functionTypeName(XPathFunctionType.concat)] = new XPathParamInfo!S(XPathFunctionType.concat, 2, size_t.max, paramType1Text);
        result[functionTypeName(XPathFunctionType.contains)] = new XPathParamInfo!S(XPathFunctionType.contains, 2, 2, paramType2Text);
        result[functionTypeName(XPathFunctionType.count)] = new XPathParamInfo!S(XPathFunctionType.count, 1, 1, paramType1NodeSet);
        result[functionTypeName(XPathFunctionType.false_)] = new XPathParamInfo!S(XPathFunctionType.false_, 0, 0, paramType1Boolean);
        result[functionTypeName(XPathFunctionType.floor)] = new XPathParamInfo!S(XPathFunctionType.floor, 1, 1, paramType1Number);
        result[functionTypeName(XPathFunctionType.id)] = new XPathParamInfo!S(XPathFunctionType.id, 1, 1, paramType1Any);
        result[functionTypeName(XPathFunctionType.lang)] = new XPathParamInfo!S(XPathFunctionType.lang, 1, 1, paramType1Text);
        result[functionTypeName(XPathFunctionType.last)] = new XPathParamInfo!S(XPathFunctionType.last, 0, 0, paramTypeEmpty);
        result[functionTypeName(XPathFunctionType.localName)] = new XPathParamInfo!S(XPathFunctionType.localName, 0, 1, paramType1NodeSet);
        result[functionTypeName(XPathFunctionType.name)] = new XPathParamInfo!S(XPathFunctionType.name, 0, 1, paramType1NodeSet);
        result[functionTypeName(XPathFunctionType.namespaceUri)] = new XPathParamInfo!S(XPathFunctionType.namespaceUri, 0, 1, paramType1NodeSet);
        result[functionTypeName(XPathFunctionType.normalizeSpace)] = new XPathParamInfo!S(XPathFunctionType.normalizeSpace, 0, 1, paramType1Text);
        result[functionTypeName(XPathFunctionType.not)] = new XPathParamInfo!S(XPathFunctionType.not, 1, 1, paramType1Boolean);
        result[functionTypeName(XPathFunctionType.number)] = new XPathParamInfo!S(XPathFunctionType.number, 0, 1, paramType1Any);
        result[functionTypeName(XPathFunctionType.position)] = new XPathParamInfo!S(XPathFunctionType.position, 0, 0, paramTypeEmpty);
        result[functionTypeName(XPathFunctionType.round)] = new XPathParamInfo!S(XPathFunctionType.round, 1, 1, paramType1Number);
        result[functionTypeName(XPathFunctionType.startsWith)] = new XPathParamInfo!S(XPathFunctionType.startsWith, 2, 2, paramType2Text);
        result[functionTypeName(XPathFunctionType.string)] = new XPathParamInfo!S(XPathFunctionType.string, 0, 1, paramType1Any);
        result[functionTypeName(XPathFunctionType.stringLength)] = new XPathParamInfo!S(XPathFunctionType.stringLength, 0, 1, paramType1Text);
        result[functionTypeName(XPathFunctionType.substring)] = new XPathParamInfo!S(XPathFunctionType.substring, 2, 3, paramType1Text2Number);
        result[functionTypeName(XPathFunctionType.substringAfter)] = new XPathParamInfo!S(XPathFunctionType.substringAfter, 2, 2, paramType2Text);
        result[functionTypeName(XPathFunctionType.substringBefore)] = new XPathParamInfo!S(XPathFunctionType.substringBefore, 2, 2, paramType2Text);
        result[functionTypeName(XPathFunctionType.sum)] = new XPathParamInfo!S(XPathFunctionType.sum, 1, 1, paramType1NodeSet);
        result[functionTypeName(XPathFunctionType.translate)] = new XPathParamInfo!S(XPathFunctionType.translate, 3, 3, paramType3Text);
        result[functionTypeName(XPathFunctionType.true_)] = new XPathParamInfo!S(XPathFunctionType.true_, 0, 0, paramType1Boolean);

        debug(debug_pham_xml_xml_xpath) if (result.maxCollision) debug writeln(__FUNCTION__, "(result.maxCollision=", result.maxCollision,
            ", result.collisionCount=", result.collisionCount, ", result.capacity=", result.capacity, ", result.length=", result.length, ")");

        return result;
    }

private:
    __gshared static XPathFunctionParamInfoTable!S _defaultFunctionParamInfoTable;
}

enum XPathScannerLexKind
{
    comma = ',',
    slash = '/',
    at = '@',
    dot = '.',
    lParens = '(',
    rParens = ')',
    lBracket = '[',
    rBracket = ']',
    star = '*',
    plus = '+',
    minus = '-',
    eq = '=',
    lt = '<',
    gt = '>',
    bang = '!',
    dollar = '$',
    apos = '\'',
    quote = '"',
    union_ = '|',
    ne = 'N', // !=
    le = 'L', // <=
    ge = 'G', // >=
    and = 'A', // &&
    or = 'O', // ||
    dotDot = 'D', // ..
    slashSlash = 'S', // //
    axe = 'a', // Axe (like child::)
    name = 'n', // XML name
    number = 'd', // Number constant
    text = 't', // Quoted string constant
    eof = 'e' // End of string
}

struct XPathScanner(S = string)
if (isXmlString!S)
{
@safe:

public:
    alias C = XmlChar!S;

public:
    this(S xpathExpression)
    in
    {
        assert(xpathExpression.length != 0);
    }
    do
    {
        _axisTypeTable = XPathAxisTypeTable!S.defaultAxisTypeTable();
        this._xPathExpression = xpathExpression;
        this._xPathExpressionLength = xpathExpression.length;
        nextChar();
        nextLex();
    }

    bool nextChar() nothrow
    in
    {
        assert(_xPathExpressionNextIndex <= _xPathExpressionLength);
    }
    do
    {
        if (_xPathExpressionNextIndex < _xPathExpressionLength)
        {
            _currentChar = _xPathExpression[_xPathExpressionNextIndex++];
            return true;
        }
        else
        {
            _currentChar = 0;
            return false;
        }
    }

    bool nextLex()
    {
        skipSpace();
        switch (currentChar)
        {
            case '\0':
                _kind = XPathScannerLexKind.eof;
                return false;
            case ',':
            case '@':
            case '(':
            case ')':
            case '|':
            case '*':
            case '[':
            case ']':
            case '+':
            case '-':
            case '=':
            case '#':
            case '$':
                _kind = currentChar;
                nextChar();
                break;
            case '<':
                _kind = XPathScannerLexKind.lt;
                nextChar();
                if (currentChar == '=')
                {
                    _kind = XPathScannerLexKind.le;
                    nextChar();
                }
                break;
            case '>':
                _kind = XPathScannerLexKind.gt;
                nextChar();
                if (currentChar == '=')
                {
                    _kind = XPathScannerLexKind.ge;
                    nextChar();
                }
                break;
            case '!':
                _kind = XPathScannerLexKind.bang;
                nextChar();
                if (currentChar == '=')
                {
                    _kind = XPathScannerLexKind.ne;
                    nextChar();
                }
                break;
            case '.':
                _kind = XPathScannerLexKind.dot;
                nextChar();
                if (currentChar == '.')
                {
                    _kind = XPathScannerLexKind.dotDot;
                    nextChar();
                }
                else if (isDigit(currentChar))
                {
                    _kind = XPathScannerLexKind.number;
                    _numberValue = scanNumberM();
                }
                break;
            case '/':
                _kind = XPathScannerLexKind.slash;
                nextChar();
                if (currentChar == '/')
                {
                    _kind = XPathScannerLexKind.slashSlash;
                    nextChar();
                }
                break;
            case '"':
            case '\'':
                _kind = XPathScannerLexKind.text;
                _textValue = scanText();
                break;
            default:
                if (isDigit(currentChar))
                {
                    _kind = XPathScannerLexKind.number;
                    _numberValue = scanNumberS();
                }
                else if (isNameStartC(currentChar))
                {
                    _kind = XPathScannerLexKind.name;
                    _prefix = null;
                    _name = scanName();
                    // "foo:bar" is one lexem not three because it doesn't allow spaces in between
                    // We should distinct it from "foo::" and need process "foo ::" as well
                    if (currentChar == ':')
                    {
                        nextChar();
                        // can be "foo:bar" or "foo::"
                        if (currentChar == ':')
                        {
                            // "foo::"
                            nextChar();
                            _kind = XPathScannerLexKind.axe;
                        }
                        else
                        {
                            // "foo:*", "foo:bar" or "foo: "
                            _prefix = _name;
                            if (currentChar == '*')
                            {
                                nextChar();
                                _name = "*";
                            }
                            else if (isNameStartC(currentChar))
                                _name = scanName();
                            else
                                throw new XmlParserException(XmlMessage.eInvalidNameAtOf, currentIndex + 1, sourceText);
                        }
                    }
                    else
                    {
                        skipSpace();
                        if (currentChar == ':')
                        {
                            nextChar();
                            // it can be "foo ::" or just "foo :"
                            if (currentChar == ':')
                            {
                                nextChar();
                                _kind = XPathScannerLexKind.axe;
                            }
                            else
                                throw new XmlParserException(XmlMessage.eInvalidNameAtOf, currentIndex + 1, sourceText);
                        }
                    }
                    skipSpace();
                    _canBeFunction = (currentChar == '(');
                }
                else
                    throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, currentChar, currentIndex + 1, sourceText);
                break;
        }

        return true;
    }

    S scanName() nothrow
    in
    {
        assert(isNameStartC(currentChar));
        assert(_xPathExpressionNextIndex >= 1);
    }
    do
    {
        const start = _xPathExpressionNextIndex - 1;
        size_t end = _xPathExpressionNextIndex - 1;
        while (currentChar != ':' && isNameInC(currentChar))
        {
            ++end;
            nextChar();
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - _xPathExpression=", _xPathExpression[start..end]);

        return _xPathExpression[start..end];
    }

    double scanNumberM() nothrow
    in
    {
        assert(isDigit(currentChar));
        assert(_xPathExpressionNextIndex >= 2);
        assert(_xPathExpression[_xPathExpressionNextIndex - 2] == '.');
    }
    do
    {
        scope (failure) assert(0, "Assume nothrow failed");

        const start = _xPathExpressionNextIndex - 2;
        size_t end = _xPathExpressionNextIndex - 1;

        while (isDigit(currentChar))
        {
            ++end;
            nextChar();
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - _xPathExpression=", _xPathExpression[start..end]);

        return _xPathExpression[start..end].to!double();
    }

    double scanNumberS() nothrow
    in
    {
        assert(currentChar == '.' || isDigit(currentChar));
        assert(_xPathExpressionNextIndex >= 1);
    }
    do
    {
        scope (failure) assert(0, "Assume nothrow failed");

        const start = _xPathExpressionNextIndex - 1;
        size_t end = _xPathExpressionNextIndex - 1;
        while (isDigit(currentChar))
        {
            ++end;
            nextChar();
        }
        if (currentChar == '.')
        {
            ++end;
            nextChar();
            while (isDigit(currentChar))
            {
                ++end;
                nextChar();
            }
        }

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - _xPathExpression=", _xPathExpression[start..end]);

        return _xPathExpression[start..end].to!double();
    }

    S scanText()
    {
        const quoteChar = currentChar;
        nextChar();
        assert(_xPathExpressionNextIndex >= 1);

        size_t start = _xPathExpressionNextIndex - 1;
        size_t end = _xPathExpressionNextIndex - 1;

        while (currentChar != quoteChar)
        {
            if (!nextChar())
                throw new XmlParserException(XmlMessage.eExpectedCharButEos, quoteChar);
            ++end;
        }

        if (currentChar != quoteChar)
            throw new XmlParserException(XmlMessage.eExpectedCharButChar, quoteChar, currentChar);

        nextChar();

        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - _xPathExpression=", _xPathExpression[start..end]);

        return _xPathExpression[start..end];
    }

    void skipSpace() nothrow
    {
        while (isSpace(currentChar) && nextChar())
        {}
    }

    @property bool canBeFunction() const nothrow
    in
    {
        assert(_kind == XPathScannerLexKind.name);
    }
    do
    {
        return _canBeFunction;
    }

    @property C currentChar() const nothrow
    {
        return _currentChar;
    }

    @property ptrdiff_t currentIndex() const nothrow
    {
        return _xPathExpressionNextIndex - 1;
    }

    @property bool isNameNodeType() const nothrow
    {
        const t = nameNodeType;
        return (prefix.length == 0) &&
            (t == XPathNodeType.comment ||
             t == XPathNodeType.all ||
             t == XPathNodeType.processingInstruction ||
             t == XPathNodeType.text);
    }

    @property bool isPrimaryExpr() const nothrow
    {
        const k = kind;
        return (k == XPathScannerLexKind.dollar) ||
            (k == XPathScannerLexKind.lParens) ||
            (k == XPathScannerLexKind.number) ||
            (k == XPathScannerLexKind.text) ||
            (k == XPathScannerLexKind.name && canBeFunction && !isNameNodeType);
    }

    @property bool isStep() const nothrow
    {
        const k = kind;
        return k == XPathScannerLexKind.at ||
            k == XPathScannerLexKind.axe ||
            k == XPathScannerLexKind.dot ||
            k == XPathScannerLexKind.dotDot ||
            k == XPathScannerLexKind.name ||
            k == XPathScannerLexKind.star;
    }

    @property C kind() const nothrow
    {
        return _kind;
    }

    @property S name() const nothrow
    {
        return _name;
    }

    @property XPathAxisType nameAxisType() const nothrow
    in
    {
        assert(kind == XPathScannerLexKind.axe);
        assert(_name.ptr !is null);
    }
    do
    {
        return _axisTypeTable.get(name);
    }

    @property XPathNodeType nameNodeType() const nothrow
    in
    {
        assert(_name.ptr !is null);
    }
    do
    {
        const n = name;
        return n == "comment" ? XPathNodeType.comment :
            n == "node" ? XPathNodeType.all :
            n == "processing-instruction" ? XPathNodeType.processingInstruction :
            n == "text" ? XPathNodeType.text :
            XPathNodeType.root;
    }

    @property double numberValue() const nothrow
    in
    {
        assert(_kind == XPathScannerLexKind.number);
    }
    do
    {
        return _numberValue;
    }

    @property S prefix() const nothrow
    in
    {
        assert(_kind == XPathScannerLexKind.name);
    }
    do
    {
        return _prefix;
    }

    @property S sourceText() const nothrow
    {
        return _xPathExpression;
    }

    @property S textValue() const nothrow
    in
    {
        assert(_kind == XPathScannerLexKind.text);
        assert(_textValue.ptr !is null);
    }
    do
    {
        return _textValue;
    }

private:
    XPathAxisTypeTable!S _axisTypeTable;
    S _prefix, _name, _textValue;
    S _xPathExpression;
    size_t _xPathExpressionNextIndex, _xPathExpressionLength;
    double _numberValue;
    C _currentChar, _kind;
    bool _canBeFunction;
}

struct XPathParser(S = string)
if (isXmlString!S)
{
public:
    alias C = XmlChar!S;

public:
    this(S xpathExpressionOrPattern)
    {
        scanner = XPathScanner!S(xpathExpressionOrPattern);
    }

    XPathNode!S parseExpression()
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", indentString(), ", sourceText=", sourceText);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseExpression(null);
        if (scanner.kind != XPathScannerLexKind.eof)
            throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar,
                scanner.currentIndex + 1, sourceText);
        return result;
    }

    XPathNode!S parsePattern()
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", indentString(), ", sourceText=", sourceText);
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parsePattern(null);
        if (scanner.kind != XPathScannerLexKind.eof)
            throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar, scanner.currentIndex + 1, sourceText);
        return result;
    }

    @property S sourceText() const nothrow
    {
        return scanner.sourceText;
    }

private:
    XPathScanner!S scanner;

    // The recursive is like
    // ParseOrExpr->ParseAndExpr->ParseEqualityExpr->parseRelationalExpr...->parseFilterExpr->parsePredicate->parseExpression
    // So put 200 limitation here will max cause about 2000~3000 depth stack.
    size_t parseDepth;
    enum maxParseDepth = 200;

    debug(debug_pham_xml_xml_xpath)
    {
        size_t nodeIndent;

        final string indentString()
        {
            return stringOfChar!string(' ', nodeIndent << 1);
        }

        final string traceString(string aMethod, XPathNode!S aInput)
        {
            import std.format : format;

            return format("%s%s(input: %s, scannerName: %s)", indentString(), aMethod,
                shortClassName(aInput), scanner.name);
        }
    }

    pragma(inline, true)
    void checkAndSkipToken(C t)
    {
        //debug(debug_pham_xml_xml_xpath) outputXmlTraceXPathParserF("%spassToken('%c') ? '%c'", indentString(), t, scanner.kind);

        checkToken(t);
        nextLex();
    }

    pragma(inline, true)
    void checkNodeSet(XPathResultType t)
    {
        debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - ", indentString());

        if (t != XPathResultType.nodeSet && t != XPathResultType.any)
            throw new XmlParserException(XmlMessage.eNodeSetExpectedAtOf, scanner.currentIndex + 1, sourceText);
    }

    pragma(inline, true)
    void checkToken(C t)
    {
        debug(debug_pham_xml_xml_xpath)debug writeln(__FUNCTION__, "(t=", t, ")");

        if (scanner.kind != t)
            throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar,
                scanner.currentIndex + 1, sourceText);
    }

    XPathAxisType getAxisType()
    {
        debug(debug_pham_xml_xml_xpath)debug writeln(__FUNCTION__, "()");

        const axis = scanner.nameAxisType();
        if (axis == XPathAxisType.error)
            throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar,
                scanner.currentIndex + 1, sourceText);
        return axis;
    }

    pragma(inline, true)
    bool isOp(scope const(C)[] opName)
    {
        debug(debug_pham_xml_xml_xpath)debug writeln(__FUNCTION__, "(opName=", opName, ")");

        return scanner.kind == XPathScannerLexKind.name &&
            scanner.prefix.length == 0 &&
            scanner.name == opName;
    }

    pragma(inline, true)
    void nextLex()
    {
        scanner.nextLex();
    }

    XPathNode!S parseExpression(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        if (++parseDepth > maxParseDepth)
            throw new XmlParserException(XmlMessage.eExpressionTooComplex, sourceText);

        XPathNode!S result = parseOrExpr(aInput);
        --parseDepth;
        return result;
    }

    // OrExpr ::= ( OrExpr 'or' )? AndExpr
    XPathNode!S parseOrExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result = parseAndExpr(aInput);

        do
        {
            if (!isOp("or"))
                return result;

            nextLex();
            result = new XPathOperator!S(result, XPathOp.or, result, parseAndExpr(aInput));
        }
        while (true);
    }

    // AndExpr ::= ( AndExpr 'and' )? EqualityExpr
    XPathNode!S parseAndExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parseEqualityExpr(aInput);

        do
        {
            if (!isOp("and"))
                return result;

            nextLex();
            result = new XPathOperator!S(result, XPathOp.and, result, parseEqualityExpr(aInput));
        }
        while (true);
    }

    // EqualityOp ::= '=' | '!='
    // EqualityExpr ::= ( EqualityExpr EqualityOp )? RelationalExpr
    XPathNode!S parseEqualityExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parseRelationalExpr(aInput);

        do
        {
            auto op = scanner.kind == XPathScannerLexKind.eq
                ? XPathOp.eq
                : (scanner.kind == XPathScannerLexKind.ne ? XPathOp.ne : XPathOp.error);
            if (op == XPathOp.error)
                return result;

            nextLex();
            result = new XPathOperator!S(result, op, result, parseRelationalExpr(aInput));
        }
        while (true);
    }

    // RelationalOp ::= '<' | '>' | '<=' | '>='
    // RelationalExpr ::= ( RelationalExpr RelationalOp )? AdditiveExpr
    XPathNode!S parseRelationalExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parseAdditiveExpr(aInput);

        do
        {
            auto op = scanner.kind == XPathScannerLexKind.lt ? XPathOp.lt :
                scanner.kind == XPathScannerLexKind.le ? XPathOp.le :
                scanner.kind == XPathScannerLexKind.gt ? XPathOp.gt :
                scanner.kind == XPathScannerLexKind.ge ? XPathOp.ge :
                XPathOp.error;
            if (op == XPathOp.error)
                return result;

            nextLex();
            result = new XPathOperator!S(result, op, result, parseAdditiveExpr(aInput));
        }
        while (true);
    }

    // AdditiveOp ::= '+' | '-'
    // AdditiveExpr ::= ( AdditiveExpr AdditiveOp )? MultiplicativeExpr
    XPathNode!S parseAdditiveExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parseMultiplicativeExpr(aInput);

        do
        {
            auto op = scanner.kind == XPathScannerLexKind.plus
                ? XPathOp.plus
                : (scanner.kind == XPathScannerLexKind.minus ? XPathOp.minus : XPathOp.error);
            if (op == XPathOp.error)
                return result;

            nextLex();
            result = new XPathOperator!S(result, op, result, parseMultiplicativeExpr(aInput));
        }
        while (true);
    }

    // MultiplicativeOp ::= '*' | 'div' | 'mod'
    // MultiplicativeExpr ::= ( MultiplicativeExpr MultiplicativeOp )? UnaryExpr
    XPathNode!S parseMultiplicativeExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parseUnaryExpr(aInput);

        do
        {
            auto op = scanner.kind == XPathScannerLexKind.star ? XPathOp.multiply :
                isOp("div") ? XPathOp.divide :
                isOp("mod") ? XPathOp.mod :
                XPathOp.error;
            if (op == XPathOp.error)
                return result;

            nextLex();
            result = new XPathOperator!S(result, op, result, parseUnaryExpr(aInput));
        }
        while (true);
    }

    // UnaryExpr ::= UnionExpr | '-' UnaryExpr
    XPathNode!S parseUnaryExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        bool minus;
        while (scanner.kind == XPathScannerLexKind.minus)
        {
            nextLex();
            minus = !minus;
        }

        if (minus)
            return new XPathOperator!S(aInput, XPathOp.multiply,
                parseUnionExpr(aInput), new XPathOperand!S(aInput, -1.0));
        else
            return parseUnionExpr(aInput);
    }

    // UnionExpr ::= ( UnionExpr '|' )? PathExpr
    XPathNode!S parseUnionExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parsePathExpr(aInput);

        do
        {
            if (scanner.kind != XPathScannerLexKind.union_)
                return result;
            checkNodeSet(result.returnType);

            nextLex();
            auto opnd2 = parsePathExpr(aInput);
            checkNodeSet(opnd2.returnType);

            result = new XPathOperator!S(result, XPathOp.union_, result, opnd2);
        }
        while (true);
    }

    // PathOp ::= '/' | '//'
    // PathExpr ::= LocationPath | FilterExpr ( PathOp  RelativeLocationPath )?
    XPathNode!S parsePathExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result;
        if (scanner.isPrimaryExpr())
        {
            // in this moment we should distinct LocationPas vs FilterExpr
            // (which starts from is PrimaryExpr)
            result = parseFilterExpr(aInput);
            if (scanner.kind == XPathScannerLexKind.slash)
            {
                nextLex();
                result = parseRelativeLocationPath(result);
            }
            else if (scanner.kind == XPathScannerLexKind.slashSlash)
            {
                nextLex();
                result = parseRelativeLocationPath(
                    new XPathAxis!S(result, XPathAxisType.descendantOrSelf, result));
            }
        }
        else
            result = parseLocationPath(null); // Must pass null

        return result;
    }

    // FilterExpr ::= PrimaryExpr | FilterExpr Predicate
    XPathNode!S parseFilterExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parsePrimaryExpr(aInput);
        while (scanner.kind == XPathScannerLexKind.lBracket) // result must be a query
            result = new XPathFilter!S(result, result, parsePredicate(result));

        return result;
    }

    // Predicate ::= '[' Expr ']'
    XPathNode!S parsePredicate(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        // we have predicates. Check that input type is NodeSet
        checkNodeSet(aInput.returnType);

        checkAndSkipToken(XPathScannerLexKind.lBracket);
        XPathNode!S result = parseExpression(aInput);
        checkAndSkipToken(XPathScannerLexKind.rBracket);

        return result;
    }

    // LocationPath ::= RelativeLocationPath | AbsoluteLocationPath
    XPathNode!S parseLocationPath(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        if (scanner.kind == XPathScannerLexKind.slash)
        {
            nextLex();
            XPathNode!S result = new XPathRoot!S(aInput);

            if (scanner.isStep)
                result = parseRelativeLocationPath(result);

            return result;
        }
        else if (scanner.kind == XPathScannerLexKind.slashSlash)
        {
            nextLex();
            return parseRelativeLocationPath(new XPathAxis!S(aInput,
                    XPathAxisType.descendantOrSelf, new XPathRoot!S(aInput)));
        }
        else
            return parseRelativeLocationPath(aInput);
    }

    // Pattern ::= ( Pattern '|' )? LocationPathPattern
    XPathNode!S parsePattern(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parseLocationPathPattern(aInput);

        do
        {
            if (scanner.kind != XPathScannerLexKind.union_)
                return result;

            nextLex();
            result = new XPathOperator!S(result, XPathOp.union_, result,
                    parseLocationPathPattern(result));
        }
        while (true);
    }

    // PathOp ::= '/' | '//'
    // RelativeLocationPath ::= ( RelativeLocationPath PathOp )? Step
    XPathNode!S parseRelativeLocationPath(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = aInput;
        do
        {
            result = parseStep(result);
            if (XPathScannerLexKind.slashSlash == scanner.kind)
            {
                nextLex();
                result = new XPathAxis!S(result, XPathAxisType.descendantOrSelf, result);
            }
            else if (XPathScannerLexKind.slash == scanner.kind)
                nextLex();
            else
                break;
        }
        while (true);

        return result;
    }

    // Step ::= '.' | '..' | ( AxisName '::' | '@' )? NodeTest Predicate*
    XPathNode!S parseStep(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result;
        if (XPathScannerLexKind.dot == scanner.kind)
        {
            // '.'
            nextLex();
            result = new XPathAxis!S(aInput, XPathAxisType.self, aInput);
        }
        else if (XPathScannerLexKind.dotDot == scanner.kind)
        {
            // '..'
            nextLex();
            result = new XPathAxis!S(aInput, XPathAxisType.parent, aInput);
        }
        else
        {
            // ( AxisName '::' | '@' )? NodeTest Predicate*
            auto axisType = XPathAxisType.child;
            switch (scanner.kind)
            {
                case XPathScannerLexKind.at: // '@'
                    axisType = XPathAxisType.attribute;
                    nextLex();
                    break;
                case XPathScannerLexKind.axe: // AxisName '::'
                    axisType = getAxisType();
                    nextLex();
                    break;
                default:
                    break;
            }

            // Need to check for axisType == XPathAxisType.namespace?
            auto nodeType = axisType == XPathAxisType.attribute ?
                XPathNodeType.attribute : XPathNodeType.element;

            result = parseNodeTest(aInput, axisType, nodeType);

            while (XPathScannerLexKind.lBracket == scanner.kind)
                result = new XPathFilter!S(result, result, parsePredicate(result));
        }
        return result;
    }

    // NodeTest ::= NameTest | 'comment ()' | 'text ()' | 'node ()' | 'processing-instruction ('  Literal ? ')'
    XPathNode!S parseNodeTest(XPathNode!S aInput, XPathAxisType axisType, XPathNodeType nodeType)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        S nodeName, nodePrefix;

        switch (scanner.kind)
        {
            case XPathScannerLexKind.name:
                if (scanner.canBeFunction && scanner.isNameNodeType)
                {
                    assert(scanner.nameNodeType != XPathNodeType.root);

                    nodePrefix = null;
                    nodeName = null;
                    nodeType = scanner.nameNodeType;
                    nextLex();

                    checkAndSkipToken(XPathScannerLexKind.lParens);

                    if (nodeType == XPathNodeType.processingInstruction)
                    {
                        if (scanner.kind != XPathScannerLexKind.rParens)
                        {
                            // 'processing-instruction (' Literal ')'
                            checkToken(XPathScannerLexKind.text);
                            nodeName = scanner.textValue;
                            nextLex();
                        }
                    }

                    checkAndSkipToken(XPathScannerLexKind.rParens);
                }
                else
                {
                    nodePrefix = scanner.prefix;
                    nodeName = scanner.name;
                    nextLex();
                }
                break;
            case XPathScannerLexKind.star:
                nodePrefix = null;
                nodeName = "*";
                nextLex();
                break;
            default:
                throw new XmlParserException(XmlMessage.eNodeSetExpectedAtOf, scanner.currentIndex + 1, sourceText);
        }

        return new XPathAxis!S(aInput, axisType, aInput, nodeType, nodePrefix, nodeName);
    }

    // PrimaryExpr ::= Literal | Number | VariableReference | '(' Expr ')' | FunctionCall
    XPathNode!S parsePrimaryExpr(XPathNode!S aInput)
    in
    {
        assert(scanner.isPrimaryExpr);
    }
    do
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result;
        switch (scanner.kind)
        {
            case XPathScannerLexKind.text:
                result = new XPathOperand!S(aInput, scanner.textValue);
                nextLex();
                break;
            case XPathScannerLexKind.number:
                result = new XPathOperand!S(aInput, scanner.numberValue);
                nextLex();
                break;
            case XPathScannerLexKind.dollar:
                nextLex();
                checkToken(XPathScannerLexKind.name);
                result = new XPathVariable!S(aInput, scanner.name, scanner.prefix);
                nextLex();
                break;
            case XPathScannerLexKind.lParens:
                nextLex();
                result = parseExpression(aInput);
                if (result.astType != XPathAstType.constant)
                    result = new XPathGroup!S(result, result);
                checkAndSkipToken(XPathScannerLexKind.rParens);
                break;
            case XPathScannerLexKind.name:
                if (scanner.canBeFunction && !scanner.isNameNodeType)
                    result = parseMethod(null);
                break;
            default:
                break;
        }

        assert(result !is null, "isPrimaryExpr() was true. We should recognize this lex.");

        return result;
    }

    XPathNode!S parseMethod(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        S name = scanner.name;
        S prefix = scanner.prefix;
        XPathNode!S[] argList;
        checkAndSkipToken(XPathScannerLexKind.name);

        checkAndSkipToken(XPathScannerLexKind.lParens);
        if (scanner.kind != XPathScannerLexKind.rParens)
        {
            do
            {
                argList ~= parseExpression(aInput);
                if (scanner.kind == XPathScannerLexKind.rParens)
                    break;
                checkAndSkipToken(XPathScannerLexKind.comma);
            }
            while (true);
        }
        checkAndSkipToken(XPathScannerLexKind.rParens);

        if (prefix.length == 0)
        {
            const XPathParamInfo!S pi = XPathFunctionParamInfoTable!S.defaultFunctionParamInfoTable().find(name);
            if (pi !is null)
            {
                if (argList.length < pi.minArgs)
                    throw new XmlParserException(XmlMessage.eInvalidNumberArgsOf, argList.length, pi.minArgs, name, sourceText);

                if (pi.functionType == XPathFunctionType.concat)
                {
                    foreach (i, a; argList)
                    {
                        if (a.returnType != XPathResultType.text)
                            argList[i] = new XPathFunction!S(aInput, XPathFunctionType.string, a);
                    }
                }
                else
                {
                    auto argCount = argList.length;
                    if (argCount > pi.maxArgs)
                        throw new XmlParserException(XmlMessage.eInvalidNumberArgsOf, argCount, pi.maxArgs, name, sourceText);

                    // argument we have the type specified (can be < pi.minArgs)
                    if (argCount > pi.argTypes.length)
                        argCount = pi.argTypes.length;

                    for (size_t i = 0; i < argCount; ++i)
                    {
                        auto a = argList[i];
                        if (pi.argTypes[i] != XPathResultType.any && pi.argTypes[i] != a.returnType)
                        {
                            switch (pi.argTypes[i])
                            {
                                case XPathResultType.boolean:
                                    argList[i] = new XPathFunction!S(aInput, XPathFunctionType.boolean, a);
                                    break;
                                case XPathResultType.nodeSet:
                                    if (!isClassType!(XPathVariable!S)(a) &&
                                        !(isClassType!(XPathFunction!S)(a) && a.returnType == XPathResultType.any))
                                        throw new XmlParserException(XmlMessage.eInvalidArgTypeOf, i, name, sourceText);
                                    break;
                                case XPathResultType.number:
                                    argList[i] = new XPathFunction!S(aInput, XPathFunctionType.number, a);
                                    break;
                                case XPathResultType.text:
                                    argList[i] = new XPathFunction!S(aInput, XPathFunctionType.string, a);
                                    break;
                                default:
                                    break;
                            }
                        }
                    }
                }

                return new XPathFunction!S(aInput, pi.functionType, argList);
            }
        }

        return new XPathFunction!S(aInput, prefix, name, argList);
    }

    // LocationPathPattern ::= '/' | RelativePathPattern | '//' RelativePathPattern |
    //  '/' RelativePathPattern |
    //  IdKeyPattern (('/' | '//') RelativePathPattern)?
    XPathNode!S parseLocationPathPattern(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S result;
        switch (scanner.kind)
        {
            case XPathScannerLexKind.slash:
                nextLex();
                result = new XPathRoot!S(aInput);
                if (scanner.kind == XPathScannerLexKind.eof ||
                    scanner.kind == XPathScannerLexKind.union_)
                    return result;
                break;
            case XPathScannerLexKind.slashSlash:
                nextLex();
                result = new XPathAxis!S(aInput, XPathAxisType.descendantOrSelf, new XPathRoot!S(aInput));
                break;
            case XPathScannerLexKind.name:
                if (scanner.canBeFunction)
                {
                    result = parseIdKeyPattern(aInput);
                    if (result !is null)
                    {
                        switch (scanner.kind)
                        {
                            case XPathScannerLexKind.slash:
                                nextLex();
                                break;
                            case XPathScannerLexKind.slashSlash:
                                nextLex();
                                result = new XPathAxis!S(aInput, XPathAxisType.descendantOrSelf, result);
                                break;
                            default:
                                return result;
                        }
                    }
                }
                break;
            default:
                break;
        }

        return parseRelativePathPattern(result);
    }

    // IdKeyPattern ::= 'id' '(' Literal ')' | 'key' '(' Literal ',' Literal ')'
    XPathNode!S parseIdKeyPattern(XPathNode!S aInput)
    in
    {
        assert(scanner.canBeFunction);
    }
    do
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        XPathNode!S[] argList;
        if (scanner.prefix.length == 0)
        {
            if (scanner.name == "id")
            {
                const XPathParamInfo!S pi = XPathFunctionParamInfoTable!S.defaultFunctionParamInfoTable().find("id");
                assert(pi !is null);

                nextLex();
                checkAndSkipToken(XPathScannerLexKind.lParens);
                checkToken(XPathScannerLexKind.text);
                argList ~= new XPathOperand!S(aInput, scanner.textValue);
                nextLex();
                checkAndSkipToken(XPathScannerLexKind.rParens);
                return new XPathFunction!S(aInput, pi.functionType, argList);
            }

            if (scanner.name == "key")
            {
                nextLex();
                checkAndSkipToken(XPathScannerLexKind.lParens);
                checkToken(XPathScannerLexKind.text);
                argList ~= new XPathOperand!S(aInput, scanner.textValue);
                nextLex();
                checkAndSkipToken(XPathScannerLexKind.comma);
                checkToken(XPathScannerLexKind.text);
                argList ~= new XPathOperand!S(aInput, scanner.textValue);
                nextLex();
                checkAndSkipToken(XPathScannerLexKind.rParens);
                return new XPathFunction!S(aInput, null, "key", argList);
            }
        }

        return null;
    }

    // PathOp ::= '/' | '//'
    // RelativePathPattern ::= ( RelativePathPattern PathOp )? StepPattern
    XPathNode!S parseRelativePathPattern(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto result = parseStepPattern(aInput);
        if (XPathScannerLexKind.slashSlash == scanner.kind)
        {
            nextLex();
            result = parseRelativePathPattern(new XPathAxis!S(result, XPathAxisType.descendantOrSelf, result));
        }
        else if (XPathScannerLexKind.slash == scanner.kind)
        {
            nextLex();
            result = parseRelativePathPattern(result);
        }
        return result;
    }

    // StepPattern ::= ChildOrAttributeAxisSpecifier NodeTest Predicate*
    // ChildOrAttributeAxisSpecifier ::= @ ? | ('child' | 'attribute') '::'
    XPathNode!S parseStepPattern(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            debug writeln(__FUNCTION__, "() - ", traceString(null, aInput));
            ++nodeIndent;
            scope (exit)
                --nodeIndent;
        }

        auto axisType = XPathAxisType.child;
        switch (scanner.kind)
        {
            case XPathScannerLexKind.at: // '@'
                axisType = XPathAxisType.attribute;
                nextLex();
                break;
            case XPathScannerLexKind.axe: // AxisName '::'
                axisType = getAxisType();
                if (axisType != XPathAxisType.child && axisType != XPathAxisType.attribute)
                    throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar,
                        scanner.currentIndex + 1, sourceText);
                nextLex();
                break;
            default:
                break;
        }

        auto nodeType = axisType == XPathAxisType.attribute ? XPathNodeType.attribute : XPathNodeType.element;

        auto result = parseNodeTest(aInput, axisType, nodeType);

        while (XPathScannerLexKind.lBracket == scanner.kind)
            result = new XPathFilter!S(result, result, parsePredicate(result));

        return result;
    }
}


// Any below codes are private
private:

void opCompare(string Op, S)(XPathOperator!S opNode, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    auto outputContext1 = inputContext.createOutputContext();
    opNode.operand1.evaluate(inputContext, outputContext1);

    auto outputContext2 = inputContext.createOutputContext();
    opNode.operand2.evaluate(inputContext, outputContext2);

    debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "() - ", inputContext.indentString);

    bool result;
    if (!outputContext1.resValue.empty && !outputContext2.resValue.empty)
    {
        auto v1 = outputContext1.resValue;
        auto v2 = outputContext2.resValue;
        normalizeValues!S(v1, v2);

        result = mixin("v1 " ~ Op ~ " v2");
    }
    else if (!outputContext1.resValue.empty && !outputContext2.resValue.empty)
    {
        for (size_t i = 0; i < outputContext1.resNodes.length; ++i)
        {
            auto e1 = outputContext1.resNodes.item(i);
            S s1 = e1.toText();
            for (size_t j = 0; j < outputContext2.resNodes.length; ++j)
            {
                auto e2 = outputContext2.resNodes.item(j);
                if (mixin("s1 " ~ Op ~ " e2.toText()"))
                {
                    outputContext.resNodes.insertBack(e1);
                    result = true;
                    break;
                }
            }
        }
    }
    else
    {
        auto v1 = !outputContext1.resValue.empty ? outputContext1.resValue : outputContext2.resValue;

        const resultNodeSet = !outputContext1.resNodes.empty;
        XmlNodeList!S nodeList2 = !outputContext1.resNodes.empty ? outputContext1.resNodes : outputContext2.resNodes;
        for (size_t i = 0; i < nodeList2.length; ++i)
        {
            auto e2 = nodeList2.item(i);
            XPathValue!S v2 = e2.toText();
            normalizeValueTo!S(v2, v1.type);

            version(none) debug(debug_pham_xml_xml_xpath) debug writeln("\t", "Op=", Op, ", e2.name=", e2.name, ", e2=", e2.toText(), ", v1=", v1.toString());

            if (mixin("v1 " ~ Op ~ " v2"))
            {
                result = true;
                if (resultNodeSet)
                    outputContext.resNodes.insertBack(e2);
                else
                    break;
            }
        }
    }

    outputContext.resValue = result;
}

void opBinary(string Op, S)(XPathOperator!S opNode, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    double v1 = opNode.operand1.get!double(inputContext);
    double v2 = opNode.operand2.get!double(inputContext);
    double result;
    if (isNaN(v1) || isNaN(v2))
        result = double.nan;
    else
    {
        static if (Op == "mod")
        {
            import std.math : fmod;

            result = fmod(v1, v2);
        }
        else
            result = mixin("v1 " ~ Op ~ " v2");
    }

    outputContext.resValue = result;
}

/**
 * boolean( expression )
 * Evaluates an expression and returns true or false
 * Params:
 *  expression = To be evaluated. The expression can refer to numbers and node-sets as well as booleans
 * Returns:
 *  A boolean true or false after evaluating expression
 */
void fctBoolean(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    bool result = context.argumentList[0].get!bool(inputContext);

    outputContext.resValue = result;
}

/**
 * ceiling( number )
 * Evaluates a decimal number and returns the smallest integer greater than or equal to the decimal number
 * Params:
 *  number = To be evaluated
 * Returns:
 *  A double - nearest integer greater than or equal to number
 */
void fctCeiling(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.math : ceil;

    double result = ceil(context.argumentList[0].get!double(inputContext));

    outputContext.resValue = result;
}

// choose( boolean, object1, object2 )
//void fctChoose(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

/**
 * concat( string1, string2 [,stringN]* )
 * Concatenates two or more strings and returns the resulting string
 * Params:
 *  string...N = Aaccepts two or more arguments. Each of these arguments is a string
 * Returns:
 *  A string that is the concatenation of all the strings passed to the function as arguments
 */
void fctConcat(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S s;
    foreach (e; context.argumentList)
        s ~= e.get!S(inputContext);

    outputContext.resValue = s;
}

/**
 * contains(haystack, needle)
 * Determines whether the first argument string contains the second argument string and returns boolean true or false
 * Params:
 *  haystack = The string to be searched
 *  needle = The string to look for as a substring of haystack
 * Returns:
 *  A boolean true if haystack contains needle. Otherwise, false
 */
void fctContains(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.string : indexOf;

    const s1 = context.argumentList[0].get!S(inputContext);
    const s2 = context.argumentList[1].get!S(inputContext);
    bool result = s1.indexOf(s2) >= 0;

    outputContext.resValue = result;
}

// count( node-set )
void fctCount(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    auto tempOutputContext = inputContext.createOutputContext();
    context.argumentList[0].evaluate(inputContext, tempOutputContext);
    double result = tempOutputContext.resNodes.length;

    outputContext.resValue = result;
}

// current()
//void fctCurrent(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

// document( URI [,node-set] )
//void fctDocument(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

// element-available( QName )
//void fctElementAvailable(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

// false()
void fctFalse(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    outputContext.resValue = false;
}

// floor( number )
void fctFloor(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.math : floor;

    double result = floor(context.argumentList[0].get!double(inputContext));

    outputContext.resValue = result;
}

// format-number( number, pattern ) | format-number( number, pattern, decimalFormat )
//void fctFormatNumber(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

// function-available( name )
//void fctFunctionAvailable(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

// generate-id( [node-set] )
//void fctGenerateId(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

// id( expression )
void fctId(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : find;
    import std.array : empty, split;

    S[] idTokens = context.argumentList[0].get!S(inputContext).split();

    bool hasId(XmlNode!S e)
    {
        if (auto a = e.findAttributeById())
        {
            S av = a.value;
            return !find(idTokens, av).empty;
        }
        else
            return false;
    }

    if (inputContext.resNodes.empty)
    {
        auto nodes = inputContext.xpathDocumentElement.getElements(null, Yes.deep);
        foreach (e; nodes)
        {
            if (hasId(e))
                outputContext.resNodes.insertBack(e);
        }
    }
    else
    {
        for (size_t i = 0; i < inputContext.resNodes.length; ++i)
        {
            auto e = inputContext.resNodes.item(i);
            auto nodes = e.getElements(null, Yes.deep);
            foreach (e2; nodes)
            {
                if (hasId(e2))
                    outputContext.resNodes.insertBack(e2);
            }
        }
    }
}

// key( keyname, value )
//void fctKey(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

// lang( string )
void fctLang(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : startsWith;

    S lan = context.argumentList[0].get!S(inputContext);

    bool hasLan(XmlNode!S e)
    {
        bool r;
        do
        {
            if (auto a = e.findAttribute("xml:lang"))
            {
                S av = a.value;
                r = av.startsWith(lan);
            }
            e = e.parent;
        }
        while (e !is null && !r);
        return r;
    }

    bool result;
    if (lan.length != 0)
    {
        for (size_t i = 0; i < inputContext.resNodes.length; ++i)
        {
            auto e = inputContext.resNodes.item(i);
            result = hasLan(e);
            if (result)
                break;
        }
    }

    outputContext.resValue = result;
}

// last()
void fctLast(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    double result = inputContext.resNodes.length;

    outputContext.resValue = result;
}

// local-name( [node-set] )
void fctLocalName(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S result;
    bool useDefault;
    if (context.argumentList.length != 0)
    {
        auto tempOutputContext = inputContext.createOutputContext();
        context.argumentList[0].evaluate(inputContext, tempOutputContext);
        if (tempOutputContext.resNodes.empty)
            useDefault = true;
        else
            result = inputContext.resNodes.front.localName;
    }
    if (useDefault && !inputContext.resNodes.empty)
        result = inputContext.resNodes.front.localName;

    outputContext.resValue = result;
}

// name( [node-set] )
void fctName(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S result;
    bool useDefault;
    if (context.argumentList.length != 0)
    {
        auto tempOutputContext = inputContext.createOutputContext();
        context.argumentList[0].evaluate(inputContext, tempOutputContext);
        if (tempOutputContext.resNodes.empty)
            useDefault = true;
        else
            result = inputContext.resNodes.front.name;
    }
    if (useDefault && !inputContext.resNodes.empty)
        result = inputContext.resNodes.front.name;

    outputContext.resValue = result;
}

// namespace-uri( [node-set] )
void fctNamespaceUri(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    S result;
    bool useDefault;
    if (context.argumentList.length != 0)
    {
        auto tempOutputContext = inputContext.createOutputContext();
        context.argumentList[0].evaluate(inputContext, tempOutputContext);
        if (tempOutputContext.resNodes.empty)
            useDefault = true;
        else
            result = inputContext.resNodes.front.namespaceUri;
    }
    if (useDefault && !inputContext.resNodes.empty)
        result = inputContext.resNodes.front.namespaceUri;

    outputContext.resValue = result;
}

/**
 * The normalize-space function strips leading and trailing white-space from a string,
 * replaces sequences of whitespace characters by a single space, and returns the resulting string.
 */
// normalize-space( [string] )
void fctNormalizeSpace(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    const s = context.argumentList.length != 0
        ? context.argumentList[0].get!S(inputContext)
        : (!inputContext.resNodes.empty
            ? inputContext.resNodes.front.toText()
            : null);

    if (s.length == 0)
    {
        outputContext.resValue = "";
        return;
    }

    size_t b = 0, e = s.length;
    while (b + 1 < e && isSpace(s[b]) && isSpace(s[b + 1]))
        b++;
    while (e > b + 1 && isSpace(s[e - 1]) && isSpace(s[e - 2]))
        e--;

    outputContext.resValue = e > b
        // Need to check for all spaces
        ? (e - b != 1 || s[b..e] != " " ? s[b..e] : "")
        : "";
}

// not( expression )
void fctNot(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    bool result = !context.argumentList[0].get!bool(inputContext);

    outputContext.resValue = result;
}

// number( [object] )
void fctNumber(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    double result = context.argumentList[0].get!double(inputContext);

    outputContext.resValue = result;
}

// position()
void fctPosition(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    double result;
    if (!inputContext.resNodes.empty)
    {
        result = inputContext.filterNodes.indexOf(inputContext.resNodes.front);
        // Convert to based 1 if found
        if (result >= 0)
            result += 1;
    }

    outputContext.resValue = result;
}

// round( decimal )
void fctRound(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.math : round;

    double result = round(context.argumentList[0].get!double(inputContext));

    outputContext.resValue = result;
}

// starts-with( haystack, needle )
void fctStartsWith(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : startsWith;

    const s1 = context.argumentList[0].get!S(inputContext);
    const s2 = context.argumentList[1].get!S(inputContext);
    bool result = s1.startsWith(s2);

    outputContext.resValue = result;
}

/**
 * string( [object] )
 * Converts the given argument to a string
 * Params:
 *  object = To be converted to a string. If omitted, the context node is used
 * Returns:
 *  A string
 */
void fctString(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    outputContext.resValue = context.get!S(inputContext);
}

// string-length( [string] )
void fctStringLength(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.uni : byCodePoint;

    const s = context.argumentList.length != 0
        ? context.argumentList[0].get!S(inputContext)
        : (!inputContext.resNodes.empty
            ? inputContext.resNodes.front.toText()
            : null);

    double result = 0.0;
    foreach (e; s.byCodePoint)
        result += 1;

    outputContext.resValue = result;
}

// substring( string, start ) | substring( string, start, length )
void fctSubstring(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.comparison : min;

    S result;
    S s = context.argumentList[0].get!S(inputContext);
    int pos = cast(int)context.argumentList[1].get!double(inputContext);
    const cnt = cast(int)context.argumentList[2].get!double(inputContext);

    // Based 1 in xpath, so convert to based 0
    --pos;
    if (cnt > 0 && pos >= 0 && pos < s.length)
        result = rightString!S(s, min(cnt, s.length - pos));
    else
        result = "";

    outputContext.resValue = result;
}

// substring-after( haystack, needle )
void fctSubstringAfter(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : findSplit;

    const s = context.argumentList[0].get!S(inputContext);
    const sub = context.argumentList[1].get!S(inputContext);
    auto searchResult = s.findSplit(sub);

    outputContext.resValue = searchResult[2];
}

// substring-before( haystack, needle )
void fctSubstringBefore(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : findSplit;

    const s = context.argumentList[0].get!S(inputContext);
    const sub = context.argumentList[1].get!S(inputContext);
    auto searchResult = s.findSplit(sub);

    if (searchResult[1] == sub)
        outputContext.resValue = searchResult[1];
    else
        outputContext.resValue = "";
}

// sum(node-set)
void fctSum(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    auto tempOutputContext = inputContext.createOutputContext();
    context.argumentList[0].evaluate(inputContext, tempOutputContext);

    double result = 0.0;
    for (size_t i = 0; i < tempOutputContext.resNodes.length; ++i)
    {
        auto e = inputContext.resNodes.item(i);
        double ev = toNumber!S(e.toText());
        if (!isNaN(ev))
            result += ev;
    }

    outputContext.resValue = result;
}

// system-property( name)
//void fctSystemProperty(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

// translate( string, abc, XYZ )
void fctTranslate(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.array : array;
    import std.string : indexOf;
    import std.uni : byCodePoint;
    import pham.utl.utl_array_append;

    const s = context.argumentList[0].get!S(inputContext);
    if (s.length == 0)
    {
        outputContext.resValue = "";
        return;
    }

    const fromS = context.argumentList[1].get!S(inputContext).byCodePoint.array;
    const toS = context.argumentList[2].get!S(inputContext).byCodePoint.array;

    Appender!S result;
    foreach (e; s.byCodePoint)
    {
        const i = fromS.indexOf(e);
        // Keep the character ?
        if (i < 0)
            result.put(e);
        // Replace the character
        else if (i < toS.length)
            result.put(toS[i]);
        // Remove the character
    }

    outputContext.resValue = result.data;
}

// true()
void fctTrue(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    outputContext.resValue = true;
}

// unparsed-entity-url( string )
//void fctUnparsedEntityUrl(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)

bool normalizeValueToBoolean(S)(ref XPathValue!S v) nothrow @trusted
if (isXmlString!S)
{
    switch (v.type)
    {
        case XPathDataType.empty:
            v = false;
            break;
        case XPathDataType.number:
            v = toBoolean(v.number);
            break;
        case XPathDataType.text:
            v = toBoolean!S(v.text);
            break;
        default:
            break;
    }
    return v.boolean;
}

double normalizeValueToNumber(S)(ref XPathValue!S v) @trusted
if (isXmlString!S)
{
    switch (v.type)
    {
        case XPathDataType.empty:
            v = 0.0;
            break;
        case XPathDataType.boolean:
            v = toNumber(v.boolean);
            break;
        case XPathDataType.text:
            v = toNumber!S(v.text);
            break;
        default:
            break;
    }
    return v.number;
}

S normalizeValueToText(S)(ref XPathValue!S v) nothrow @trusted
if (isXmlString!S)
{
    switch (v.type)
    {
        case XPathDataType.empty:
            v = "";
            break;
        case XPathDataType.boolean:
            v = toText!S(v.boolean);
            break;
        case XPathDataType.number:
            v = toText!S(v.number);
            break;
        default:
            break;
    }
    return v.text;
}

void normalizeValueTo(S)(ref XPathValue!S v, const XPathDataType toT)
if (isXmlString!S)
{
    debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(v=", v, ", toT=", toT, ")");

    const fromT = v.type;
    if (fromT != toT)
    {
        final switch (toT)
        {
            case XPathDataType.boolean:
                normalizeValueToBoolean!S(v);
                break;
            case XPathDataType.number:
                normalizeValueToNumber!S(v);
                break;
            case XPathDataType.empty:
            case XPathDataType.text:
                normalizeValueToText!S(v);
                break;
        }
    }
}

void normalizeValues(S)(ref XPathValue!S value1, ref XPathValue!S value2)
if (isXmlString!S)
{
    debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value1=", value1, ", value2=", value2, ")");

    const t1 = value1.type;
    const t2 = value2.type;

    if (t1 != t2)
    {
        if (t1 == XPathDataType.number || t2 == XPathDataType.number)
        {
            if (t1 != XPathDataType.number)
                normalizeValueToNumber!S(value1);
            if (t2 != XPathDataType.number)
                normalizeValueToNumber!S(value2);
        }
        else
        {
            if (t1 != XPathDataType.text)
                normalizeValueToText!S(value1);
            if (t2 != XPathDataType.text)
                normalizeValueToText!S(value2);
        }
    }
}

bool toBoolean(double value) nothrow pure
{
    return !isNaN(value) && value != 0;
}

bool toBoolean(S)(scope const(XmlChar!S)[] value) nothrow pure
if (isXmlString!S)
{
    debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

    return value == "1" || value == XmlConst!S.boolTrue || value == XmlConst!S.yes;
}

double toNumber(bool value) nothrow pure
{
    return value ? 1.0 : 0.0;
}

double toNumber(S)(scope const(XmlChar!S)[] value) pure
if (isXmlString!S)
{
    import std.string : strip;

    debug(debug_pham_xml_xml_xpath) debug writeln(__FUNCTION__, "(value=", value, ")");

    value = strip(value);
    return value.length == 0 ? double.nan : value.to!double();
}

S toText(S)(bool value) nothrow pure
if (isXmlString!S)
{
    return value ? XmlConst!S.boolTrue : XmlConst!S.boolFalse;
}

S toText(S)(double value) nothrow
if (isXmlString!S)
{
    import std.math : isInfinity, signbit;

    scope (failure) assert(0, "Assume nothrow failed");

    if (isNaN(value))
        return signbit(value) ? XmlConst!S.floatNNaN : XmlConst!S.floatPNaN;
    else if (isInfinity(value))
        return signbit(value) ? XmlConst!S.floatNInf : XmlConst!S.floatPInf;
    else
        return value.to!S();
}

S toText(S)(XmlNode!S node)
if (isXmlString!S)
{
    return node.hasValue(No.checkContent) ? node.value : node.innerText;
}


unittest  // XPathParser
{
    import std.file : write; // write parser tracer info to file

    string[] output;
    XPathParser!string xpathParser;

    string getOutput()
    {
        string s = output[0];
        foreach (e; output[1..$])
            s ~= "\n" ~ e;
        return s;
    }

    void toOutput(XPathNode!string r)
    {
        output ~= xpathParser.sourceText.idup;
        output ~= r.outerXml();
        output ~= "\n";
    }

    xpathParser = XPathParser!string("count(/restaurant/tables/table)");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book[1]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book/title[@lang='eng']");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("//title[@lang='eng']");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("//title");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book/title");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore//title[@lang]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book[3]/*");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string(`/bookstore//book[title="Harry Potter"]`);
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book[1]/title/@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("/bookstore/book/title/@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("//book//@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("//@lang");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("title");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("./title");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("book[last()]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("book/author[last()]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("(book/author)[last()]");
    toOutput(xpathParser.parseExpression());

    //xpathParser = XPathParser!string("degree[position() &lt; 3]");
    xpathParser = XPathParser!string("degree[position() < 3]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("x/y[position() = 1]");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("id('foo')");
    toOutput(xpathParser.parseExpression());

    xpathParser = XPathParser!string("id('foo')/child::para[position()=5]");
    toOutput(xpathParser.parseExpression());

    write("xpath_parser_ast.log", getOutput);
}

unittest  // XPathParser.selectNodes
{
    import pham.xml.xml_test;

    auto doc = new XmlDocument!string().load(xpathXml);
    auto nodeList = doc.documentElement.selectNodes("descendant::book[author/last-name='Austen']");

    assert(nodeList.length == 3);
    assert(nodeList.front.getAttribute("publicationdate") == "1997");
    assert(nodeList.moveFront.name == "book");
    assert(nodeList.front.getAttribute("publicationdate") == "1991");
    assert(nodeList.moveFront.name == "book");
    assert(nodeList.front.getAttribute("publicationdate") == "1982");
    assert(nodeList.moveFront.name == "book");

    //writeln("nodeList.length: ", nodeList.length);
    //foreach (e; nodeList)
    //    writeln("nodeName: ", e.name, ", position: ", e.position);
}

unittest // fctNormalizeSpace
{
    {
        auto context = new XPathFunction!string(null, XPathFunctionType.normalizeSpace, new XPathOperand!string(null, ""));
        XPathContext!string inputContext, outputContext;
        fctNormalizeSpace(context, inputContext, outputContext);
        assert(outputContext.resValue.toString() == "");
    }

    {
        auto context = new XPathFunction!string(null, XPathFunctionType.normalizeSpace, new XPathOperand!string(null, "     "));
        XPathContext!string inputContext, outputContext;
        fctNormalizeSpace(context, inputContext, outputContext);
        assert(outputContext.resValue.toString() == "", "<" ~ outputContext.resValue.toString() ~ ">");
    }

    {
        auto context = new XPathFunction!string(null, XPathFunctionType.normalizeSpace, new XPathOperand!string(null, " abc     "));
        XPathContext!string inputContext, outputContext;
        fctNormalizeSpace(context, inputContext, outputContext);
        assert(outputContext.resValue.toString() == " abc ");
    }

    {
        auto context = new XPathFunction!string(null, XPathFunctionType.normalizeSpace, new XPathOperand!string(null, "XYz "));
        XPathContext!string inputContext, outputContext;
        fctNormalizeSpace(context, inputContext, outputContext);
        assert(outputContext.resValue.toString() == "XYz ");
    }

    {
        auto context = new XPathFunction!string(null, XPathFunctionType.normalizeSpace, new XPathOperand!string(null, "AbC"));
        XPathContext!string inputContext, outputContext;
        fctNormalizeSpace(context, inputContext, outputContext);
        assert(outputContext.resValue.toString() == "AbC");
    }
}

unittest // fctTranslate
{
    {
        auto context = new XPathFunction!string(null, XPathFunctionType.normalizeSpace, [new XPathOperand!string(null, ""),
            new XPathOperand!string(null, "abcdefghijklmnopqrstuvwxyz"), new XPathOperand!string(null, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")]);
        XPathContext!string inputContext, outputContext;
        fctTranslate(context, inputContext, outputContext);
        assert(outputContext.resValue.toString() == "", outputContext.resValue.toString());
    }

    {
        auto context = new XPathFunction!string(null, XPathFunctionType.normalizeSpace, [new XPathOperand!string(null, "The quick brown fox."),
            new XPathOperand!string(null, "abcdefghijklmnopqrstuvwxyz"), new XPathOperand!string(null, "ABCDEFGHIJKLMNOPQRSTUVWXYZ")]);
        XPathContext!string inputContext, outputContext;
        fctTranslate(context, inputContext, outputContext);
        assert(outputContext.resValue.toString() == "THE QUICK BROWN FOX.", outputContext.resValue.toString());
    }

    {
        auto context = new XPathFunction!string(null, XPathFunctionType.normalizeSpace, [new XPathOperand!string(null, "The quick brown fox."),
            new XPathOperand!string(null, "brown"), new XPathOperand!string(null, "red")]);
        XPathContext!string inputContext, outputContext;
        fctTranslate(context, inputContext, outputContext);
        assert(outputContext.resValue.toString() == "The quick red fdx.", outputContext.resValue.toString());
    }
}

