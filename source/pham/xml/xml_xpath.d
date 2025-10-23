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
import std.math : isInfinity, isNaN, signbit;
import std.typecons : Flag, No, Yes;

debug(debug_pham_xml_xml_xpath) import std.stdio : stdout, writeln;
debug(debug_pham_xml_xml_xpath) import pham.utl.utl_array_append : Appender;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_enum_set : EnumArray, toName;
import pham.utl.utl_object : singleton;
import pham.utl.utl_text : shortClassName;
import pham.utl.utl_trait : maxSize;
import pham.xml.xml_buffer;
import pham.xml.xml_dom;
import pham.xml.xml_exception;
import pham.xml.xml_message;
import pham.xml.xml_object;
import pham.xml.xml_type;
import pham.xml.xml_util;

@safe:

//version = XPathXmlNodeList;

//TODO DMD v2.111.0 Compiler bug when using XmlNodeList, compiler never stop
version(XPathXmlNodeList)
{
    template XmlPathNodeList(S)
    {
        alias XmlPathNodeList = XmlNodeList!S;
    }

    pragma(inline, true)
    private XmlPathNodeList!S nullList(S)() nothrow pure @safe
    {
        return XmlPathNodeList!S(null);
    }
}
else
{
    template XmlPathNodeList(S)
    {
        alias XmlPathNodeList = XmlNode!S[];
    }

    pragma(inline, true)
    private XmlNode!S[] nullList(S)() nothrow pure @safe
    {
        return null;
    }

    pragma(inline, true)
    private bool empty(S)(scope const(XmlNode!S)[] nodes) nothrow pure @safe
    {
        return nodes.length == 0;
    }

    pragma(inline, true)
    private inout(XmlNode!S) front(S)(inout(XmlNode!S)[] nodes) nothrow pure @safe
    {
        return nodes[0];
    }

    pragma(inline, true)
    private ptrdiff_t indexOf(S)(scope const(XmlNode!S)[] nodes, scope const(XmlNode!S) node) nothrow pure @trusted
    {
        import pham.utl.utl_array : indexOf;

        return (cast(const(void*)[])nodes).indexOf(cast(const(void*))node);
    }

    private inout(XmlNode!S) moveFront(S)(ref inout(XmlNode!S)[] nodes) nothrow pure @safe
    {
        auto result = nodes[0];
        nodes = nodes[1..$];
        return result;
    }
}

/**
 * Returns first node of matching xpath expression
 * Params:
 *  source = a context node to search from
 *  xpath = a xpath expression string
 * Returns:
 *  a node, XmlNode, of matching xpath expression or null if no matching found
 */
XmlNode!S selectNode(S = string)(XmlNode!S source, S xpath)
if (isXmlString!S)
{
    auto resultList = selectNodes(source, xpath);
    return !resultList.empty ? resultList.front : null;
}

/**
 * Returns node-list of matching xpath expression
 * Params:
 *  source = a context node to search from
 *  xpath = a xpath expression string
 * Returns:
 *  a node-list, XmlPathNodeList, of matching xpath expression
 */
XmlPathNodeList!S selectNodes(S = string)(XmlNode!S source, S xpath)
if (isXmlString!S)
{
    auto xpathParser = XPathParser!S(xpath);
    auto xpathExpression = xpathParser.parseExpression();

    auto inputContext = XPathContext!S(source);
    inputContext.putRes(source);

    auto outputContext = inputContext.createOutputContext();
    xpathExpression.evaluate(inputContext, outputContext);

    return outputContext.resNodes;
}

alias selectSingleNode = selectNode;

XPathValue!S evaluate(S = string)(XmlNode!S source, S xpath)
if (isXmlString!S)
{
    auto xpathParser = XPathParser!S(xpath);
    auto xpathExpression = xpathParser.parseExpression();

    auto inputContext = XPathContext!S(source);
    inputContext.putRes(source);

    auto outputContext = inputContext.createOutputContext();
    xpathExpression.evaluate(inputContext, outputContext);

    return outputContext.resValue;
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
    nodeSet,
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
    number,
    text,
    nodeSet,
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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("value=", value));

        this._type = XPathDataType.boolean;
        this._boolean = value;
    }

    this(double value) nothrow pure
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("value=", toText!string(value)));

        this._type = XPathDataType.number;
        this._number = value;
    }

    this(S value) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("value=", value));

        this._type = XPathDataType.text;
        this._text = value;
    }

    this(scope const(C)[] value) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("value=", value));

        this._type = XPathDataType.text;
        this._text = value.idup;
    }

    this(XmlPathNodeList!S value) nothrow @trusted
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);
        debug(debug_pham_xml_xml_xpath) traceFunction();

        this._type = XPathDataType.nodeSet;
        this._nodes = value;
    }

    version(none)
    this(typeof(this) source) nothrow @trusted
	{
        this._type = source._type;
        final switch (source._type)
        {
            case XPathDataType.boolean:
                this._boolean = source._boolean;
                break;
            case XPathDataType.number:
                this._number = source._number;
                break;
            case XPathDataType.text:
                this._text = source._text;
                break;
            case XPathDataType.nodeSet:
                this._nodes = source._nodes;
                break;
            case XPathDataType.empty:
                break;
        }
    }

    ~this() nothrow
    {
        if (_type != XPathDataType.empty)
            doClear();
    }

    void opAssign(bool rhs) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("rhs=", rhs));

        if (_type != XPathDataType.boolean)
            clear();

        this._type = XPathDataType.boolean;
        this._boolean = rhs;
    }

    void opAssign(double rhs) nothrow
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("rhs=", toText!string(rhs)));

        if (_type != XPathDataType.number)
            clear();

        this._type = XPathDataType.number;
        this._number = rhs;
    }

    void opAssign(S rhs) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("rhs=", rhs));

        if (_type != XPathDataType.text)
            clear();

        this._type = XPathDataType.text;
        this._text = rhs;
    }

    void opAssign(scope const(C)[] rhs) nothrow @trusted
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("rhs=", rhs));

        if (_type != XPathDataType.text)
            clear();

        this._type = XPathDataType.text;
        this._text = rhs.idup;
    }

    void opAssign(XmlPathNodeList!S rhs) nothrow @trusted
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);
        debug(debug_pham_xml_xml_xpath) traceFunction();

        if (_type != XPathDataType.nodeSet)
            clear();

        this._type = XPathDataType.nodeSet;
        this._nodes = rhs;
    }

    void opAssign(typeof(this) rhs) nothrow @trusted
    {
        clear();

        this._type = rhs._type;
        final switch (rhs._type)
        {
            case XPathDataType.boolean:
                this._boolean = rhs._boolean;
                break;
            case XPathDataType.number:
                this._number = rhs._number;
                break;
            case XPathDataType.text:
                this._text = rhs._text;
                break;
            case XPathDataType.nodeSet:
                this._nodes = rhs._nodes;
                break;
            case XPathDataType.empty:
                break;
        }
    }

    bool opCast(B: bool)() const nothrow @trusted
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        final switch (_type)
        {
            case XPathDataType.boolean:
                return _boolean;
            case XPathDataType.number:
                return !isNaN(_number) && _number != 0;
            case XPathDataType.text:
                return _text.length != 0;
            case XPathDataType.nodeSet:
                return _nodes.length != 0;
            case XPathDataType.empty:
                return false;
        }
    }

	bool opEquals(ref typeof(this) rhs)
	{
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("this=", this.toString(), ", rhs=", rhs.toString()));

        return opCmp(rhs) == 0;
	}

	int opCmp(ref typeof(this) rhs) @trusted
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        import std.uni : sicmp;

        int result;
        if (this.type == rhs.type)
        {
            final switch (this.type)
            {
                case XPathDataType.boolean:
                    result = cast(int)this._boolean - cast(int)(rhs._boolean);
                    break;
                case XPathDataType.number:
                    import std.math : cmp;
                    result = cmp(this._number, rhs._number);
                    break;
                case XPathDataType.text:
                    result = sicmp(this._text, rhs._text);
                    break;
                case XPathDataType.nodeSet:
                    const rhsLen = rhs._nodes.length;
                    result = 0;
                    foreach (i, e; this._nodes)
                    {
                        if (i >= rhsLen)
                            break;
                        result = sicmp(toText!S(e), toText!S(rhs._nodes[i]));
                        if (result != 0)
                            break;
                    }
                    if (result == 0)
                    {
                        const thisLen = this._nodes.length;
                        if (thisLen > rhsLen)
                            result = 1;
                        else if (thisLen < rhsLen)
                            result = -1;
                    }
                    break;
                case XPathDataType.empty:
                    result = 0;
                    break;
            }
        }
        else if (this.type == XPathDataType.empty || rhs.type == XPathDataType.empty)
            result = cast(int)XPathDataType.empty - cast(int)rhs.empty;
        else
            result = sicmp(this.toString(), rhs.toString());

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(.text("this=", this.toString(), ", rhs=", rhs.toString(), ", result=", result));

        return result;
    }

    void clear() nothrow
    {
        if (_type != XPathDataType.empty)
            doClear();
    }

    T get(T)() @trusted
    if (is(T == S) || is(T == double) || is(T == ptrdiff_t) || is(T == bool))
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        static if (is(T == S))
        {
            version(XPathXmlNodeList) pragma(msg, __FUNCTION__ ~ "." ~ T.stringof);

            final switch (_type)
            {
                case XPathDataType.text:
                    return _text;
                case XPathDataType.boolean:
                    return toText!S(_boolean);
                case XPathDataType.number:
                    return toText!S(_number);
                case XPathDataType.nodeSet:
                    return _nodes.length == 1 ? firstNodeText() : null;
                case XPathDataType.empty:
                    return null;
            }
        }
        else static if (is(T == double))
        {
            version(XPathXmlNodeList) pragma(msg, __FUNCTION__ ~ "." ~ T.stringof);

            final switch (_type)
            {
                case XPathDataType.number:
                    return _number;
                case XPathDataType.boolean:
                    return toNumber(_boolean);
                case XPathDataType.text:
                    return toNumber!S(_text);
                case XPathDataType.nodeSet:
                    return _nodes.length == 1 ? toNumber!S(firstNodeText()) : double.nan;
                case XPathDataType.empty:
                    return double.nan;
            }
        }
        else static if (is(T == ptrdiff_t))
        {
            version(XPathXmlNodeList) pragma(msg, __FUNCTION__ ~ "." ~ T.stringof);

            final switch (_type)
            {
                case XPathDataType.number:
                    return toInteger(_number);
                case XPathDataType.boolean:
                    return toInteger(_boolean);
                case XPathDataType.text:
                    return toInteger(toNumber!S(_text));
                case XPathDataType.nodeSet:
                    return _nodes.length == 1 ? toInteger(toNumber!S(firstNodeText())) : -1;
                case XPathDataType.empty:
                    return -1;
            }
        }
        else static if (is(T == bool))
        {
            version(XPathXmlNodeList) pragma(msg, __FUNCTION__ ~ "." ~ T.stringof);

            final switch (_type)
            {
                case XPathDataType.boolean:
                    return _boolean;
                case XPathDataType.number:
                    return toBoolean(_number);
                case XPathDataType.text:
                    return toBoolean!S(_text);
                case XPathDataType.nodeSet:
                    return _nodes.length == 1 ? toBoolean!S(firstNodeText()) : false;
                case XPathDataType.empty:
                    return false;
            }
        }
        else
            static assert(0, "Unsupported type " ~ T.stringof);
    }

    void put(XmlNode!S node)
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        asNodes() ~= node;
    }

    S toString() @trusted
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        final switch (_type)
        {
            case XPathDataType.boolean:
                return toText!S(_boolean);
            case XPathDataType.number:
                return toText!S(_number);
            case XPathDataType.text:
                return _text;
            case XPathDataType.nodeSet:
                return toStringNodeSet();
            case XPathDataType.empty:
                return null;
        }
    }

    debug(debug_pham_xml_xml_xpath) ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context) @trusted
    {
        final switch (_type)
        {
            case XPathDataType.boolean:
                return sink.put(toText!string(_boolean));
            case XPathDataType.number:
                return sink.put(toText!string(_number));
            case XPathDataType.text:
                return sink.put(_text);
            case XPathDataType.nodeSet:
                return sink.put(toStringNodeSet());
            case XPathDataType.empty:
                return sink;
        }
    }

    @property bool boolean() const nothrow @trusted
    in
    {
        assert(_type == XPathDataType.empty || _type == XPathDataType.boolean);
    }
    do
    {
        return _type == XPathDataType.boolean ? _boolean : false;
    }

    @property bool empty() const nothrow
    {
        return _type == XPathDataType.empty;
    }

    @property ptrdiff_t length() @trusted
    {
        return _type == XPathDataType.nodeSet
            ? _nodes.length
            : (_type == XPathDataType.text ? _text.length : -1);
    }

    @property ref XmlPathNodeList!S nodes() nothrow return @trusted
    in
    {
        assert(_type == XPathDataType.empty || _type == XPathDataType.nodeSet);
    }
    do
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        static XmlPathNodeList!S _emptyNodeSet = nullList!S();
        return _type == XPathDataType.nodeSet ? _nodes : _emptyNodeSet;
    }

    @property double number() const nothrow @trusted
    in
    {
        assert(_type == XPathDataType.empty || _type == XPathDataType.number);
    }
    do
    {
        return _type == XPathDataType.number ? _number : double.nan;
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
            case XPathDataType.nodeSet:
                return XPathResultType.nodeSet;
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

protected:
    ref XmlPathNodeList!S asNodes() nothrow return @trusted
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        if (_type != XPathDataType.nodeSet)
        {
            clear();

            _type = XPathDataType.nodeSet;
            _nodes = nullList!S();
        }
        return _nodes;
    }

    void doClear() nothrow @trusted
    {
        // Do not log or use any codes using string (GC data) since it can be called from destructor
        final switch (_type)
        {
            case XPathDataType.text:
                _text = null;
                break;
            case XPathDataType.nodeSet:
                _nodes = nullList!S();
                break;
            case XPathDataType.empty:
            case XPathDataType.boolean:
            case XPathDataType.number:
                break;
        }

        _type = XPathDataType.empty;
        _dummy[] = 0;
    }

    S firstNodeText() @trusted
    in
    {
        assert(_type == XPathDataType.nodeSet);
        assert(_nodes.length == 1);
    }
    do
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        return toText!S(_nodes.front);
    }

    S toStringNodeSet() @trusted
    in
    {
        assert(_type == XPathDataType.nodeSet);
    }
    do
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        const len = _nodes.length;
        if (len == 0)
            return null;

        if (len == 1)
            return toText!S(_nodes.front);

        auto result = Appender!S(len * 8 + 2);
        result.put("[");
        foreach (i, e; _nodes)
        {
            if (i)
                result.put(",");
            result.put(toText!S(e));
        }
        return result.put("]").data;
    }

protected:
    union
    {
        ubyte[maxSize!(XmlPathNodeList!S, S, double)] _dummy;  // First member to be initialized to all zero
        XmlPathNodeList!S _nodes;
        S _text;           // 8 or 16 bytes depending on pointer size
        double _number;    // 8 bytes
        bool _boolean;     // 1 byte
    }

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

    this(XmlNode!S xpathNode) nothrow
    {
        this._xpathNode = xpathNode;
        this._xpathDocument = xpathNode.document;
        this.equalName = xpathNode.document.equalName;
    }

    pragma(inline, true)
    void clearRes() nothrow
    {
        resValue.clear();
    }

    XPathContext!S createOutputContext() nothrow
    {
        XPathContext!S result;
        result._xpathNode = this._xpathNode;
        result._xpathDocument = this._xpathDocument;
        result._xpathDocumentElement = this._xpathDocumentElement;
        result.equalName = this.equalName;
        result.filterNodes = this.filterNodes;
        result.variables = this.variables;
        return result;
    }

    pragma(inline, true)
    void putRes(XmlNode!S node)
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        resValue.put(node);
    }

    void putRes(XmlPathNodeList!S nodes)
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        foreach (e; nodes)
            resValue.put(e);
    }

    pragma(inline, true)
    ref XmlPathNodeList!S resNodes() nothrow
    {
        version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

        return resValue.nodes;
    }

    pragma(inline, true)
    @property size_t hasResNodes()
    {
        return resValue.type == XPathDataType.nodeSet ? resValue.length : 0;
    }

    pragma(inline, true)
    @property bool hasResValue() const nothrow
    {
        return !resValue.empty;
    }

    @property XmlDocument!S xpathDocument() nothrow
    {
        return _xpathDocument;
    }

    @property XmlElement!S xpathDocumentElement() nothrow
    {
        if (_xpathDocumentElement is null)
            _xpathDocumentElement = xpathDocument.documentElement;
        return _xpathDocumentElement;
    }

    @property XmlNode!S xpathNode() nothrow
    {
        return _xpathNode;
    }

public:
    XmlDocument!S.EqualName equalName;

    XmlPathNodeList!S filterNodes;
    Dictionary!(S, XPathValue!S) variables;

    XPathValue!S resValue;

private:
    XmlDocument!S _xpathDocument;
    XmlElement!S _xpathDocumentElement;
    XmlNode!S _xpathNode;
}

abstract class XPathNode(S = string) : XmlObject!S
{
@safe:

public:
    abstract void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext);

    T evaluate(T)(ref XPathContext!S inputContext)
    if (is(T == S) || is(T == double) || is(T == ptrdiff_t) || is(T == bool))
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("T=", T.stringof));

        T result;
        debug(debug_pham_xml_xml_xpath) scope (exit) { incNodeIndent(); traceFunctionPar(text("result=", result)); decNodeIndent(); }

        auto tempOutputContext = inputContext.createOutputContext();
        evaluate(inputContext, tempOutputContext);

        static if (is(T == S) || is(T == double) || is(T == ptrdiff_t) || is(T == bool))
        {
            result = tempOutputContext.resValue.get!T();
            return result;
        }
        else
            static assert(0, "Unsupported type " ~ T.stringof);
    }

    debug(debug_pham_xml_xml_xpath) abstract ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context);

    @property final XPathNode!S parent() nothrow
    {
        return _parent;
    }

    @property final S qualifiedName() const nothrow
    {
        return _qualifiedName;
    }

    @property abstract XPathAstType astType() const nothrow;
    @property abstract XPathResultType returnType() const nothrow;

protected:
    alias XPathAstNodeEvaluate = void delegate(ref XPathContext!S inputContext, ref XPathContext!S outputContext);

protected:
    final void evaluateError(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath) debug stdout.flush();

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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("axisType=", axisType.toName(),
            ", nodetype=", nodetype.toName(), ", prefix=", prefix, ", localName=", localName, ", input=", shortClassName(input)));

        this._parent = parent;
        this._input = input;
        this._axisType = axisType;
        this._axisNodeType = nodetype;
        this._prefix = prefix;
        this._localName = localName;
        this._qualifiedName = combineName!S(prefix, localName);
        this._xmlNodeType = toXmlNodeType(nodetype);
        this._matchAnyName = localName == "*" && (prefix.length == 0 || prefix == "*")
            ? MatchAnyName.both
            : localName == "*"
                ? MatchAnyName.localName
                : prefix == "*"
                    ? MatchAnyName.prefix
                    : MatchAnyName.none;

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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("axisType=", axisType.toName(), ", input=", shortClassName(input)));

        this(parent, axisType, input, XPathNodeType.all, null, null);
        this._abbreviated = true;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunction();
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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

    debug(debug_pham_xml_xml_xpath) final override ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context)
    {
        putIndent(sink)
            .put(shortClassName(this))
            .put("::")
            .put(qualifiedName.to!string())
            .put("(")
            .put("axisType=")
            .put(axisType.to!string())
            .put(", nodeType=")
            .put(nodeType.to!string())
            .put(", abbreviated=")
            .put(abbreviated.to!string())
            .put(")")
            .put("\n");

        if (input !is null)
        {
            incNodeIndent();
            scope (exit)
                decNodeIndent();
            input.toString(sink, context);
        }

        return sink;
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
    enum MatchAnyName : ubyte { none, prefix, localName, both }

    final bool accept(ref XPathContext!S inputContext, XmlNode!S node) nothrow
    {
        // XmlNodeType.unknown = all
        bool result = _xmlNodeType == XmlNodeType.unknown || node.nodeType == _xmlNodeType;

        if (result && _matchAnyName != MatchAnyName.both)
        {
            if (result && _matchAnyName != MatchAnyName.prefix && prefix.length != 0)
                result = inputContext.equalName(prefix, node.prefix);

            if (result && _matchAnyName != MatchAnyName.localName && localName.length != 0)
                result = inputContext.equalName(localName, node.localName);
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("node.name=", node.name, ", result=", result));

        return result;
    }

    final void evaluateAncestor(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            auto p = e.parent;
            while (p !is null)
            {
                if (accept(inputContext, p))
                    outputContext.putRes(p);
                p = p.parent;
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateAncestorOrSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (accept(inputContext, e))
                outputContext.putRes(e);

            auto p = e.parent;
            while (p !is null)
            {
                if (accept(inputContext, p))
                    outputContext.putRes(p);
                p = p.parent;
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateAttribute(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (e.nodeType == XmlNodeType.element && e.hasAttributes)
            {
                auto attributes = e.attributes;
                foreach (a; attributes)
                {
                    if (accept(inputContext, a))
                        outputContext.putRes(a);
                }
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateChild(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (!e.hasChildNodes)
                continue;

            auto childNodes = e.childNodes;
            foreach (e2; childNodes)
            {
                if (accept(inputContext, e2))
                    outputContext.putRes(e2);
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateDescendant(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            auto childNodes = e.getChildNodes(null, Yes.deep);
            foreach (e2; childNodes)
            {
                if (accept(inputContext, e2))
                    outputContext.putRes(e2);
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateDescendantOrSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (e.nodeType != XmlNodeType.attribute && accept(inputContext, e))
                outputContext.putRes(e);

            auto childNodes = e.getChildNodes(null, Yes.deep);
            foreach (e2; childNodes)
            {
                if (accept(inputContext, e2))
                    outputContext.putRes(e2);
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateFollowing(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.nextSibling;
            if (n !is null && accept(inputContext, n))
                outputContext.putRes(n);
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateFollowingSibling(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.nextSibling;
            while (n !is null)
            {
                if (accept(inputContext, n))
                    outputContext.putRes(n);
                n = n.nextSibling;
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateNamespace(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (e.nodeType != XmlNodeType.element || !e.hasAttributes)
                continue;

            auto attributes = e.attributes;
            foreach (a; attributes)
            {
                if (accept(inputContext, a))
                    outputContext.putRes(a);
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateParent(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            auto p = e.parent;
            if (p !is null && accept(inputContext, p))
                outputContext.putRes(p);
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluatePreceding(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.previousSibling;
            if (n !is null && accept(inputContext, n))
                outputContext.putRes(n);
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluatePrecedingSibling(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (e.nodeType == XmlNodeType.attribute)
                continue;

            auto n = e.previousSibling;
            while (n !is null)
            {
                if (accept(inputContext, n))
                    outputContext.putRes(n);
                n = n.previousSibling;
            }
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

    final void evaluateSelf(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            if (accept(inputContext, e))
                outputContext.putRes(e);
        }

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContext.resNodes.length=", outputContext.resNodes.length));
    }

protected:
    XPathAstNodeEvaluate evaluateFct;
    XPathNode!S _input;
    XPathAxisType _axisType;
    XPathNodeType _axisNodeType;
    XmlNodeType _xmlNodeType;
    MatchAnyName _matchAnyName;
    bool _abbreviated;
}

class XPathFilter(S = string) : XPathNode!S
{
@safe:

public:
    this(XPathNode!S parent, XPathNode!S input, XPathNode!S condition) nothrow
    {
        debug(debug_pham_xml_xml_xpath) traceFunction();

        this._parent = parent;
        this._input = input;
        this._condition = condition;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunction();
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        auto outputContextEval = inputContext.createOutputContext();
        input.evaluate(inputContext, outputContextEval);

        if (!outputContextEval.hasResNodes)
            return;

        auto outputContextCond = outputContextEval.createOutputContext();
        auto inputContextCond = outputContextEval.createOutputContext();
        inputContextCond.filterNodes = outputContextEval.resNodes;

        auto inputNodes = outputContextEval.resNodes;
        foreach (i, e; inputNodes)
        {
            inputContextCond.clearRes();
            inputContextCond.putRes(e);

            outputContextCond.clearRes();
            condition.evaluate(inputContextCond, outputContextCond);

            if (outputContextCond.resValue.empty)
                continue;

            auto v = outputContextCond.resValue;
            bool vB = false;
            final switch (v.type)
            {
                case XPathDataType.number:
                    vB = v.get!ptrdiff_t() == (i + 1); // +1=Based 1 index
                    break;
                case XPathDataType.text:
                    vB = v.get!S().length != 0;
                    break;
                case XPathDataType.boolean:
                    vB = v.get!bool();
                    break;
                case XPathDataType.nodeSet:
                    vB = true; // Save all from input
                    break;
                case XPathDataType.empty:
                    assert(false); // Already checked above
            }
            if (vB)
                outputContext.putRes(e);

            debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("e.name=", e.name, ", vB=", vB));
        }
    }

    debug(debug_pham_xml_xml_xpath) final override ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context)
    {
        putIndent(sink)
            .put(shortClassName(this))
            .put("\n");

        incNodeIndent();
        scope (exit)
            decNodeIndent();
        _input.toString(sink, context);
        _condition.toString(sink, context);

        return sink;
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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("functionType=", functionType));

        this._parent = parent;
        this._functionType = functionType;
        this._argumentList = argumentList; //argumentList.dup();

        setEvaluateFct();
    }

    this(XPathNode!S parent, S prefix, S localName, XPathNode!S[] argumentList)
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("prefix=", prefix, ", localName=", localName));

        this._parent = parent;
        this._functionType = XPathFunctionType.userDefined;
        this._prefix = prefix;
        this._localName = localName;
        this._qualifiedName = combineName!S(prefix, localName);
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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("functionType=", functionType));

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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("functionType=", functionType));

        this._parent = parent;
        this._functionType = functionType;
        this._argumentList ~= argument;

        setEvaluateFct();
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(text("functionType=", functionType, ", localName=", _localName));
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        return evaluateFct(this, inputContext, outputContext);
    }

    debug(debug_pham_xml_xml_xpath) final override ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context)
    {
        putIndent(sink)
            .put(shortClassName(this))
            .put("::")
            .put(qualifiedName.to!string())
            .put("(")
            .put(")")
            .put(": ")
            .put(returnType.to!string())
            .put("\n");

        if (argumentList.length != 0)
        {
            incNodeIndent();
            scope (exit)
                decNodeIndent();
            foreach (ref e; argumentList)
                e.toString(sink, context);
        }

        return sink;
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
            return userDefinedEvaluateFct.returnType;
        else
            return functionResultType(functionType);
    }

protected:
    final void setEvaluateFct()
    {
        auto defaultFunctionTable = XPathFunctionTable!S.defaultFunctionTable();
        if (functionType != XPathFunctionType.userDefined)
        {
            const functionName = functionTypeName(functionType);
            if (!defaultFunctionTable.find(functionName, evaluateFct))
                throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), functionName);

            _prefix = "fn";
            _localName = functionName;
            _qualifiedName = combineName!S(_prefix, _localName);
        }
        else
        {
            auto found = defaultFunctionTable.find(qualifiedName, userDefinedEvaluateFct);
            if (!found && prefix.length != 0)
                found = defaultFunctionTable.find(localName, userDefinedEvaluateFct);
            if (!found)
                throw new XmlInvalidOperationException(XmlMessage.eInvalidOpDelegate, shortClassName(this), qualifiedName);

            evaluateFct = userDefinedEvaluateFct.evaluate;
        }
    }

protected:
    XPathUserDefinedFunctionEntry!S userDefinedEvaluateFct;
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
        debug(debug_pham_xml_xml_xpath) traceFunction();

        this._parent = parent;
        this._groupNode = groupNode;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunction();
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        auto outputContextEval = inputContext.createOutputContext();
        groupNode.evaluate(inputContext, outputContextEval);
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("outputContextEval.hasResNodes=", outputContextEval.hasResNodes));
        outputContext.resValue = outputContextEval.resValue;
    }

    debug(debug_pham_xml_xml_xpath) final override ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context)
    {
        putIndent(sink)
            .put(shortClassName(this))
            .put("\n");

        incNodeIndent();
        scope (exit)
            decNodeIndent();
        groupNode.toString(sink, context);

        return sink;
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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("value=", value));

        this._parent = parent;
        this._value = value;
    }

    this(XPathNode!S parent, double value) nothrow
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("value=", value.toText!string()));

        this._parent = parent;
        this._value = value;
    }

    this(XPathNode!S parent, S value) nothrow
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("value=", value));

        this._parent = parent;
        this._value = value;
    }

    final T evaluate(T)(ref XPathContext!S inputContext)
    if (is(T == S) || is(T == double) || is(T == bool))
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("value=", value.toString()));

        return _value.get!T();
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("value=", value.toString()));

        outputContext.resValue = value;
    }

    debug(debug_pham_xml_xml_xpath) final override ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context)
    {
        putIndent(sink)
            .put(shortClassName(this))
            .put("=");
        _value.toString(sink, context)
            .put("\n");

        return sink;
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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("opType=", toName(opType)));

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
            traceFunctionPar(text("opType=", toName(_opType)));
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        return evaluateFct(inputContext, outputContext);
    }

    debug(debug_pham_xml_xml_xpath) final override ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context)
    {
        putIndent(sink)
            .put(shortClassName(this))
            .put("::")
            .put(qualifiedName.to!string())
            .put("(")
            .put(")")
            .put(": ")
            .put(returnType.to!string())
            .put("\n");

        incNodeIndent();
        scope (exit)
            decNodeIndent();
        operand1.toString(sink, context);
        operand2.toString(sink, context);

        return sink;
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
        auto result = operand1.evaluate!bool(inputContext);
        if (result)
            result = operand2.evaluate!bool(inputContext);

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
        auto result = operand1.evaluate!bool(inputContext);
        if (!result)
            result = operand2.evaluate!bool(inputContext);

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
        auto inputNodes = tempOutputContext1.resNodes;
        foreach (e; inputNodes)
            outputContext.putRes(e);

        auto tempOutputContext2 = inputContext.createOutputContext();
        operand2.evaluate(inputContext, tempOutputContext2);
        auto inputNodes2 = tempOutputContext2.resNodes;
        foreach (e; inputNodes2)
            outputContext.putRes(e);
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

        _prefix = "op";
        _localName = toName(opType);
        _qualifiedName = combineName!S(_prefix, _localName);
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
        debug(debug_pham_xml_xml_xpath) traceFunction();

        this._parent = parent;
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath) traceFunction();

        outputContext.putRes(inputContext.xpathDocumentElement);
    }

    debug(debug_pham_xml_xml_xpath) final override ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context)
    {
        putIndent(sink)
            .put(shortClassName(this))
            .put("\n");

        return sink;
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
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("prefix=", prefix, ", localName=", localName));

        this._parent = parent;
        this._prefix = prefix;
        this._localName = localName;
        this._qualifiedName = combineName!S(prefix, localName);
    }

    final override void evaluate(ref XPathContext!S inputContext, ref XPathContext!S outputContext)
    {
        debug(debug_pham_xml_xml_xpath) traceFunction();

        auto result = qualifiedName in inputContext.variables;
        if (result is null && prefix.length != 0)
            result = localName in inputContext.variables;

        if (result is null)
        {
            debug(debug_pham_xml_xml_xpath) debug stdout.flush();

            throw new XmlInvalidOperationException(XmlMessage.eInvalidVariableName, qualifiedName);
        }

        outputContext.resValue = *result;
    }

    debug(debug_pham_xml_xml_xpath) final override ref Appender!string toString(return ref Appender!string sink, ref XPathContext!S context)
    {
        putIndent(sink)
            .put(shortClassName(this))
            .put("::")
            .put(qualifiedName.to!string)
            .put("\n");

        return sink;
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

class XPathUserDefinedFunctionEntry(S = string) : XmlObject!S
{
@safe:

public:
    this(S prefix, S localName, XPathResultType resultType,
        XPathFunctionTable!S.XPathFunctionEvaluate evaluate) nothrow
    {
        this._prefix = prefix;
        this._localName = localName;
        this._qualifiedName = combineName!S(prefix, localName);
        this._resultType = resultType;
        this._evaluate = evaluate;
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

enum XPathScannerLexKind : char
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
        this._axisTypeTable = XPathAxisTypeTable!S.defaultAxisTypeTable();
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
        debug(debug_pham_xml_xml_xpath) scope (exit) traceFunctionPar(text("_kind=", _kind, ", _currentChar=", _currentChar));

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
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(text("beg.", toString()));
            incNodeIndent();
            scope (exit)
            {
                decNodeIndent();
                traceFunctionPar(text("end.", toString()));
            }
        }

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
                            {
                                debug(debug_pham_xml_xml_xpath) debug stdout.flush();

                                throw new XmlParserException(XmlMessage.eInvalidNameAtOf, currentIndex + 1, sourceText);
                            }
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
                            {
                                debug(debug_pham_xml_xml_xpath) debug stdout.flush();

                                throw new XmlParserException(XmlMessage.eInvalidNameAtOf, currentIndex + 1, sourceText);
                            }
                        }
                    }
                    skipSpace();
                    _canBeFunction = currentChar == '(';
                }
                else
                {
                    debug(debug_pham_xml_xml_xpath) debug stdout.flush();

                    throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, currentChar, currentIndex + 1, sourceText);
                }
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

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("_xPathExpression=", _xPathExpression[start..end]));

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

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("_xPathExpression=", _xPathExpression[start..end]));

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

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("_xPathExpression=", _xPathExpression[start..end]));

        return _xPathExpression[start..end].to!double();
    }

    S scanText()
    {
        const quoteChar = currentChar;
        nextChar();
        assert(_xPathExpressionNextIndex >= 1);

        const start = _xPathExpressionNextIndex - 1;
        size_t end = _xPathExpressionNextIndex - 1;

        while (currentChar != quoteChar)
        {
            if (!nextChar())
            {
                debug(debug_pham_xml_xml_xpath) debug stdout.flush();

                throw new XmlParserException(XmlMessage.eExpectedCharButEos, quoteChar);
            }
            ++end;
        }

        if (currentChar != quoteChar)
        {
            debug(debug_pham_xml_xml_xpath) debug stdout.flush();

            throw new XmlParserException(XmlMessage.eExpectedCharButChar, quoteChar, currentChar);
        }

        nextChar();

        debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("_xPathExpression=", _xPathExpression[start..end]));

        return _xPathExpression[start..end];
    }

    void skipSpace() nothrow
    {
        while (isSpace(currentChar) && nextChar())
        {}
    }

    debug(debug_pham_xml_xml_xpath) string toString() const nothrow
    {
        return text("name=", _name, ", kind=", _kind, ", currentChar=", _currentChar);
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
    S _prefix, _name;
    S _textValue;
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
        this.scanner = XPathScanner!S(xpathExpressionOrPattern);
    }

    XPathNode!S parseExpression()
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(text("sourceText=", sourceText));
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        XPathNode!S result = parseExpression(null);
        if (scanner.kind != XPathScannerLexKind.eof)
        {
            debug(debug_pham_xml_xml_xpath) debug stdout.flush();

            throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar, scanner.currentIndex + 1, sourceText);
        }
        return result;
    }

    XPathNode!S parsePattern()
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(text("sourceText=", sourceText));
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        XPathNode!S result = parsePattern(null);
        if (scanner.kind != XPathScannerLexKind.eof)
        {
            debug(debug_pham_xml_xml_xpath) debug stdout.flush();

            throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar, scanner.currentIndex + 1, sourceText);
        }
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

    pragma(inline, true)
    void checkAndSkipToken(C t)
    {
        //debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("t=", t));

        checkToken(t);
        nextLex();
    }

    pragma(inline, true)
    void checkNodeSet(XPathResultType t)
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(scanner, text(", t=", t));

        if (t != XPathResultType.nodeSet && t != XPathResultType.any)
        {
            debug(debug_pham_xml_xml_xpath) debug stdout.flush();

            throw new XmlParserException(XmlMessage.eNodeSetExpectedAtOf, scanner.currentIndex + 1, sourceText);
        }
    }

    pragma(inline, true)
    void checkToken(C t)
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(scanner, text(", t=", t));

        if (scanner.kind != t)
        {
            debug(debug_pham_xml_xml_xpath) debug stdout.flush();

            throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar, scanner.currentIndex + 1, sourceText);
        }
    }

    XPathAxisType getAxisType()
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(scanner);

        const axis = scanner.nameAxisType();
        if (axis == XPathAxisType.error)
        {
            debug(debug_pham_xml_xml_xpath) debug stdout.flush();

            throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar, scanner.currentIndex + 1, sourceText);
        }
        return axis;
    }

    pragma(inline, true)
    bool isOp(scope const(C)[] opName)
    {
        debug(debug_pham_xml_xml_xpath) traceFunctionPar(scanner, text(", opName=", opName));

        return scanner.kind == XPathScannerLexKind.name &&
            scanner.prefix.length == 0 &&
            scanner.name == opName;
    }

    pragma(inline, true)
    bool nextLex()
    {
        return scanner.nextLex();
    }

    XPathNode!S parseExpression(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        if (++parseDepth > maxParseDepth)
        {
            debug(debug_pham_xml_xml_xpath) debug stdout.flush();

            throw new XmlParserException(XmlMessage.eExpressionTooComplex, sourceText);
        }

        XPathNode!S result = parseOrExpr(aInput);
        --parseDepth;
        return result;
    }

    // OrExpr ::= ( OrExpr 'or' )? AndExpr
    XPathNode!S parseOrExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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

    // UnaryExpr ::= UnionExpr | '-' UnaryExpr | '+' UnaryExpr
    XPathNode!S parseUnaryExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        bool minus;
        while (scanner.kind == XPathScannerLexKind.minus)
        {
            nextLex();
            minus = !minus;
        }
        while (scanner.kind == XPathScannerLexKind.plus)
            nextLex();

        return minus
            ? new XPathOperator!S(aInput, XPathOp.multiply, parseUnionExpr(aInput), new XPathOperand!S(aInput, -1.0))
            : parseUnionExpr(aInput);
    }

    // UnionExpr ::= ( UnionExpr '|' )? PathExpr
    XPathNode!S parseUnionExpr(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
                auto descendantOrSelf = new XPathAxis!S(result, XPathAxisType.descendantOrSelf, result);
                result = parseRelativeLocationPath(descendantOrSelf);
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            auto descendantOrSelf = new XPathAxis!S(aInput, XPathAxisType.descendantOrSelf, new XPathRoot!S(aInput));
            return parseRelativeLocationPath(descendantOrSelf);
        }
        else
            return parseRelativeLocationPath(aInput);
    }

    // Pattern ::= ( Pattern '|' )? LocationPathPattern
    XPathNode!S parsePattern(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
        }

        auto result = parseLocationPathPattern(aInput);

        do
        {
            if (scanner.kind != XPathScannerLexKind.union_)
                return result;

            nextLex();
            result = new XPathOperator!S(result, XPathOp.union_, result, parseLocationPathPattern(result));
        }
        while (true);
    }

    // PathOp ::= '/' | '//'
    // RelativeLocationPath ::= ( RelativeLocationPath PathOp )? Step
    XPathNode!S parseRelativeLocationPath(XPathNode!S aInput)
    {
        debug(debug_pham_xml_xml_xpath)
        {
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            const nodeType = axisType == XPathAxisType.attribute ? XPathNodeType.attribute : XPathNodeType.element;
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
                            debug(debug_pham_xml_xml_xpath) traceFunctionPar(scanner, " ?name1?");
                            nextLex();
                        }
                    }

                    checkAndSkipToken(XPathScannerLexKind.rParens);
                }
                else
                {
                    nodePrefix = scanner.prefix;
                    nodeName = scanner.name;
                    debug(debug_pham_xml_xml_xpath) traceFunctionPar(scanner, " ?name2?");
                    nextLex();
                }
                break;
            case XPathScannerLexKind.star:
                nextLex();
                if (scanner.kind == XPathScannerLexKind.name)
                {
                    nodePrefix = "*";
                    nodeName = scanner.name;
                    nextLex();
                }
                else
                {
                    nodePrefix = null;
                    nodeName = "*";
                }
                debug(debug_pham_xml_xml_xpath) traceFunctionPar(scanner, " ?star?");
                break;
            default:
                debug(debug_pham_xml_xml_xpath) debug stdout.flush();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
                {
                    debug(debug_pham_xml_xml_xpath) debug stdout.flush();

                    throw new XmlParserException(XmlMessage.eInvalidNumberArgsOf, argList.length, pi.minArgs, name, sourceText);
                }

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
                    {
                        debug(debug_pham_xml_xml_xpath) debug stdout.flush();

                        throw new XmlParserException(XmlMessage.eInvalidNumberArgsOf, argCount, pi.maxArgs, name, sourceText);
                    }

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
                                    {
                                        debug(debug_pham_xml_xml_xpath) debug stdout.flush();

                                        throw new XmlParserException(XmlMessage.eInvalidArgTypeOf, i + 1, name, sourceText);
                                    }
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
            traceFunctionPar(scanner, aInput);
            incNodeIndent();
            scope (exit)
                decNodeIndent();
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
                {
                    debug(debug_pham_xml_xml_xpath) debug stdout.flush();

                    throw new XmlParserException(XmlMessage.eInvalidTokenAtOf, scanner.currentChar, scanner.currentIndex + 1, sourceText);
                }
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

debug(debug_pham_xml_xml_xpath)
{
    import std.conv : text;
    import pham.utl.utl_text : shortFunctionName, stringOfChar;

    package void decNodeIndent()
    {
        nodeIndent--;
    }

    package void incNodeIndent()
    {
        nodeIndent++;
    }

    package ref Appender!string putIndent(return ref Appender!string sink)
    {
        return stringOfChar(sink, nodeIndent * 2, ' ');
    }

    package void traceFunction(string fullName = __FUNCTION__)
    {
        debug writeln(stringOfChar(nodeIndent * 2, ' '), shortFunctionName(2, fullName),
            "()");
    }

    package void traceFunctionPar(string inputs,
        string fullName = __FUNCTION__)
    {
        debug writeln(stringOfChar(nodeIndent * 2, ' '), shortFunctionName(2, fullName),
            "(", inputs, ")");
    }

    package void traceFunctionPar(ref XPathScanner!string scanner, XPathNode!string input,
        string fullName = __FUNCTION__)
    {
        debug writeln(stringOfChar(nodeIndent * 2, ' '), shortFunctionName(2, fullName),
            "(scanner=", scanner.toString(), ", input=", shortClassName(input), ")");
    }

    package void traceFunctionPar(ref XPathScanner!string scanner, string inputs = null,
        string fullName = __FUNCTION__)
    {
        if (inputs.length == 0)
        {
            debug writeln(stringOfChar(nodeIndent * 2, ' '), shortFunctionName(2, fullName),
                "(scanner=", scanner.toString(), ")");
        }
        else
        {
            debug writeln(stringOfChar(nodeIndent * 2, ' '), shortFunctionName(2, fullName),
                "(scanner=", scanner.toString(), inputs, ")");
        }
    }

    package size_t nodeIndent;
}


// Any below codes are private
private:

void opBinary(string Op, S)(XPathOperator!S opNode, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

    static isZero(double v) nothrow pure @safe
    {
        pragma(inline, true)
        return v == 0.0 || v == -0.0;
    }

    const v1 = opNode.operand1.evaluate!double(inputContext);
    const v2 = opNode.operand2.evaluate!double(inputContext);

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
        {
            result = mixin("v1 " ~ Op ~ " v2");
        }
    }

    outputContext.resValue = isZero(result) ? 0.0 : result;
}

void opCompare(string Op, S)(XPathOperator!S opNode, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    version(XPathXmlNodeList) pragma(msg, __FUNCTION__);
    debug(debug_pham_xml_xml_xpath) traceFunction();

    auto outputContext1 = inputContext.createOutputContext();
    opNode.operand1.evaluate(inputContext, outputContext1);

    auto outputContext2 = inputContext.createOutputContext();
    opNode.operand2.evaluate(inputContext, outputContext2);

    bool result = false;
    const hasResNodes1 = outputContext1.hasResNodes;
    const hasResNodes2 = outputContext2.hasResNodes;
    if (hasResNodes1 || hasResNodes2)
    {
        if (hasResNodes1 && hasResNodes2)
        {
            auto inputNodes1 = outputContext1.resNodes;
            auto inputNodes2 = outputContext2.resNodes;
            foreach (e1; inputNodes1)
            {
                const s1 = e1.toText!S();
                foreach (e2; inputNodes2)
                {
                    if (mixin("s1 " ~ Op ~ " e2.toText!S()"))
                    {
                        outputContext.putRes(e1);
                        result = true;
                        break;
                    }
                }
            }
        }
        else
        {
            const resultNodeSet = hasResNodes1 != 0;
            auto v1 = hasResNodes2 ? outputContext1.resValue : outputContext2.resValue;
            auto inputNodes2 = hasResNodes2 ? outputContext2.resNodes : outputContext1.resNodes;
            foreach (e2; inputNodes2)
            {
                XPathValue!S v2 = e2.toText!S();
                normalizeValueTo!S(v2, v1.type);
                if (mixin("v1 " ~ Op ~ " v2"))
                {
                    result = true;
                    if (resultNodeSet)
                        outputContext.putRes(e2);
                    else
                        break;
                }
            }
        }
    }
    else
    {
        auto v1 = outputContext1.resValue;
        auto v2 = outputContext2.resValue;
        normalizeValues!S(v1, v2);

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
    auto result = context.argumentList[0].evaluate!bool(inputContext);

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

    auto result = ceil(context.argumentList[0].evaluate!double(inputContext));

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
        s ~= e.evaluate!S(inputContext);

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

    const s1 = context.argumentList[0].evaluate!S(inputContext);
    const s2 = context.argumentList[1].evaluate!S(inputContext);
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

    auto result = floor(context.argumentList[0].evaluate!double(inputContext));

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

    S[] idTokens = context.argumentList[0].evaluate!S(inputContext).split();

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
                outputContext.putRes(e);
        }
    }
    else
    {
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
            auto nodes = e.getElements(null, Yes.deep);
            foreach (e2; nodes)
            {
                if (hasId(e2))
                    outputContext.putRes(e2);
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

    S lan = context.argumentList[0].evaluate!S(inputContext);

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
        auto inputNodes = inputContext.resNodes;
        foreach (e; inputNodes)
        {
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
        auto inputNodes = tempOutputContext.resNodes;
        if (inputNodes.empty)
            useDefault = true;
        else
            result = inputNodes.front.localName;
    }

    if (useDefault)
    {
        auto inputNodes = inputContext.resNodes;
        if (!inputNodes.empty)
            result = inputNodes.front.localName;
    }

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
        auto inputNodes = tempOutputContext.resNodes;
        if (inputNodes.empty)
            useDefault = true;
        else
            result = inputNodes.front.name;
    }

    if (useDefault)
    {
        auto inputNodes = inputContext.resNodes;
        if (!inputNodes.empty)
            result = inputNodes.front.name;
    }

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
        auto inputNodes = tempOutputContext.resNodes;
        if (inputNodes.empty)
            useDefault = true;
        else
            result = inputNodes.front.namespaceUri;
    }

    if (useDefault)
    {
        auto inputNodes = inputContext.resNodes;
        if (!inputNodes.empty)
            result = inputNodes.front.namespaceUri;
    }

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
        ? context.argumentList[0].evaluate!S(inputContext)
        : inputContext.resValue.get!S();

    if (s.length == 0)
    {
        outputContext.resValue = "";
        return;
    }

    // Trim begin & end spaces
    size_t b = 0, e = s.length;
    while (b < e && isSpace(s[b]))
        b++;
    while (e > b && isSpace(s[e - 1]))
        e--;
    if (e <= b)
    {
        outputContext.resValue = "";
        return;
    }

    const count = e - b;
    if (count <= 3)
    {
        outputContext.resValue = s[b..e];
        return;
    }

    // Check for inner spaces
    Appender!string buffer;
    const iE = e - 1;
    size_t i = b;
    while (i < iE)
    {
        if (isSpace(s[i]))
        {
            const iB = i;
            // No need to check for out of bound because the ending
            // char is not space in this while loop
            while (isSpace(s[i + 1]))
                i++;
            // Has consecutive spaces?
            if (i > iB)
            {
                // We did not append to buffer until now
                if (buffer.length == 0)
                    buffer.put(s[b..iB]);

                buffer.put(' ');
            }
            else
                i++;
        }
        else
        {
            if (buffer.length)
                buffer.put(s[i]);
            i++;
        }
    }
    // Last char
    if (buffer.length)
        buffer.put(s[e - 1]);
    outputContext.resValue = buffer.length ? buffer.data : s[b..e];
}

// not( expression )
void fctNot(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    auto result = !context.argumentList[0].evaluate!bool(inputContext);

    outputContext.resValue = result;
}

// number( [object] )
void fctNumber(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    auto result = context.argumentList.length != 0
        ? context.argumentList[0].evaluate!double(inputContext)
        : inputContext.resValue.get!double();

    outputContext.resValue = result;
}

// position()
void fctPosition(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext) @trusted
{
    double result = 0;
    auto inputNodes = inputContext.resNodes;
    if (!inputNodes.empty)
    {
        const i = inputContext.filterNodes.indexOf(inputNodes.front);
        // Convert to based 1 if found
        if (i >= 0)
            result = i + 1;
    }

    outputContext.resValue = result;
}

double fctRound(double value) nothrow @safe
{
    import std.math : round;

    if (isNaN(value))
        return value;

    const result = round(value);
    return (value - result == 0.5) ? result + 1 : result;
}

// round( decimal )
void fctRound(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    const value = context.argumentList[0].evaluate!double(inputContext);

    outputContext.resValue = fctRound(value);
}

// starts-with( haystack, needle )
void fctStartsWith(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : startsWith;

    const s1 = context.argumentList[0].evaluate!S(inputContext);
    const s2 = context.argumentList[1].evaluate!S(inputContext);
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
    auto result = context.argumentList.length != 0
        ? context.argumentList[0].evaluate!S(inputContext)
        : inputContext.resValue.get!S();

    outputContext.resValue = result;
}

// string-length( [string] )
void fctStringLength(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.uni : byCodePoint;

    const s = context.argumentList.length != 0
        ? context.argumentList[0].evaluate!S(inputContext)
        : inputContext.resValue.get!S();

    double result = 0.0;
    foreach (e; s.byCodePoint)
        result += 1;

    outputContext.resValue = result;
}

// substring( string, start ) | substring( string, start, length )
void fctSubstring(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.comparison : min;

    const s = context.argumentList[0].evaluate!S(inputContext).to!dstring();
    if (s.length == 0)
    {
        outputContext.resValue = "";
        return;
    }

    // -1=Position is based 1 in xpath, so convert to based 0
    auto indexTemp = fctRound(context.argumentList[1].evaluate!double(inputContext)) - 1;
    if (isNaN(indexTemp) || s.length <= indexTemp)
    {
        outputContext.resValue = "";
        return;
    }

    // Has count paremter?
    if (context.argumentList.length >= 3)
    {
        auto countTemp = context.argumentList[2].evaluate!double(inputContext);
        if (isNaN(countTemp))
        {
            outputContext.resValue = "";
            return;
        }

        if (indexTemp < 0 || countTemp < 0)
        {
            countTemp = indexTemp + countTemp;
            // NOTE: condition is true for NaN
            if (!(countTemp > 0))
            {
                outputContext.resValue = "";
                return;
            }
            indexTemp = 0;
        }

        const double maxLength = s.length - indexTemp;
        if (countTemp > maxLength)
            countTemp = maxLength;

        const index = toInteger(indexTemp);
        outputContext.resValue = s[index..index + toInteger(countTemp)].to!string;
        return;
    }

    const index = indexTemp < 0 ? 0 : toInteger(indexTemp);
    outputContext.resValue = s[index..$].to!string;
}

// substring-after( haystack, needle )
void fctSubstringAfter(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : findSplit;

    const s = context.argumentList[0].evaluate!S(inputContext);
    const sub = context.argumentList[1].evaluate!S(inputContext);
    auto searchResult = s.findSplit(sub);

    outputContext.resValue = searchResult.length >= 3 ? searchResult[2] : "";
}

// substring-before( haystack, needle )
void fctSubstringBefore(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    import std.algorithm.searching : findSplit;

    const s = context.argumentList[0].evaluate!S(inputContext);
    const sub = context.argumentList[1].evaluate!S(inputContext);
    auto searchResult = s.findSplit(sub);

    if (searchResult.length >= 2 && searchResult[1] == sub)
        outputContext.resValue = searchResult[0];
    else
        outputContext.resValue = "";
}

// sum(node-set)
void fctSum(S)(XPathFunction!S context, ref XPathContext!S inputContext, ref XPathContext!S outputContext)
{
    auto tempOutputContext = inputContext.createOutputContext();
    context.argumentList[0].evaluate(inputContext, tempOutputContext);

    double result = 0.0;
    auto inputNodes = tempOutputContext.resNodes;
    foreach (e; inputNodes)
    {
        const ev = toNumber!S(e.toText!S());
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

    const s = context.argumentList[0].evaluate!S(inputContext);
    if (s.length == 0)
    {
        outputContext.resValue = "";
        return;
    }

    const fromS = context.argumentList[1].evaluate!S(inputContext).byCodePoint.array;
    const toS = context.argumentList[2].evaluate!S(inputContext).byCodePoint.array;

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

ref XPathValue!S normalizeValueToBoolean(S)(return ref XPathValue!S v) @safe
if (isXmlString!S)
{
    version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

    if (v.type != XPathDataType.boolean)
        v = v.get!bool();
    return v;
}

ref XPathValue!S normalizeValueToNumber(S)(return ref XPathValue!S v) @safe
if (isXmlString!S)
{
    version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

    if (v.type != XPathDataType.number)
        v = v.get!double();
    return v;
}

ref XPathValue!S normalizeValueToText(S)(return ref XPathValue!S v) @safe
if (isXmlString!S)
{
    version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

    if (v.type != XPathDataType.text)
        v = v.get!S();
    return v;
}

ref XPathValue!S normalizeValueTo(S)(return ref XPathValue!S v, const XPathDataType toT)
if (isXmlString!S)
{
    version(XPathXmlNodeList) pragma(msg, __FUNCTION__);
    debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("v=", v, ", toT=", toT.toName()));

    const fromT = v.type;
    if (fromT != toT)
    {
        final switch (toT)
        {
            case XPathDataType.text:
            case XPathDataType.empty:
            case XPathDataType.nodeSet:
                return normalizeValueToText!S(v);
            case XPathDataType.number:
                return normalizeValueToNumber!S(v);
            case XPathDataType.boolean:
                return normalizeValueToBoolean!S(v);
        }
    }
    return v;
}

void normalizeValues(S)(ref XPathValue!S value1, ref XPathValue!S value2)
if (isXmlString!S)
{
    version(XPathXmlNodeList) pragma(msg, __FUNCTION__);
    debug(debug_pham_xml_xml_xpath) traceFunctionPar(text("value1=", value1, ", value2=", value2));

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

pragma(inline, true)
bool toBoolean(double value) nothrow pure
{
    return !isNaN(value) && value != 0;
}

pragma(inline, true)
bool toBoolean(S)(S value) nothrow pure
if (isXmlString!S)
{
    return value.length != 0;
}

pragma(inline, true)
ptrdiff_t toInteger(bool value) nothrow pure
{
    return value ? 1 : 0;
}

pragma(inline, true)
ptrdiff_t toInteger(double value) nothrow
{
    return isNaN(value) ? -1 : cast(ptrdiff_t)cast(long)fctRound(value);
}

pragma(inline, true)
double toNumber(bool value) nothrow pure
{
    return value ? 1.0 : 0.0;
}

double toNumber(S)(S value) nothrow pure
if (isXmlString!S)
{
    import std.string : strip;

    value = strip(value);

    if (value.length == 0)
        return double.nan;
    else if (value == XmlConst!S.floatNNaN)
        return -double.nan;
    else if (value == XmlConst!S.floatPNaN)
        return double.nan;
    else if (value == XmlConst!S.floatNInf)
        return -double.infinity;
    else if (value == XmlConst!S.floatPNaN)
        return double.infinity;

    try
    {
        return value.to!double();
    }
    catch (Exception)
        return double.nan;
}

S toText(S)(bool value) nothrow pure
if (isXmlString!S)
{
    return value ? XmlConst!S.boolTrue : XmlConst!S.boolFalse;
}

S toText(S)(double value) nothrow
if (isXmlString!S)
{
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
    version(XPathXmlNodeList) pragma(msg, __FUNCTION__);

    return node.hasValue(No.checkContent) ? node.value : node.innerText;
}

debug(debug_pham_xml_xml_xpath) ref Appender!string put(return ref Appender!string sink, bool value)
{
    return sink.put(value ? XmlConst!string.boolTrue : XmlConst!string.boolFalse);
}

debug(debug_pham_xml_xml_xpath) ref Appender!string put(return ref Appender!string sink, double value)
{
    if (isNaN(value))
        return sink.put(signbit(value) ? XmlConst!string.floatNNaN : XmlConst!string.floatPNaN);
    else if (isInfinity(value))
        return sink.put(signbit(value) ? XmlConst!string.floatNInf : XmlConst!string.floatPInf);
    else
        return sink.put(value.to!string());
}

debug(debug_pham_xml_xml_xpath) ref Appender!string put(return ref Appender!string sink, scope const(char)[] value)
{
    return sink.put(value);
}

version(unittest) import pham.xml.xml_test;

debug(debug_pham_xml_xml_xpath)
unittest  // XPathParser
{
    import std.file : write; // write parser tracer info to file
    import pham.utl.utl_array_append : Appender;

    Appender!string output;
    XPathContext!string xpathContext;
    XPathParser!string xpathParser;

    void toOutput(XPathNode!string r)
    {
        nodeIndent = 0;

        output.put(xpathParser.sourceText)
            .put("\n");
        r.toString(output, xpathContext)
            .put("\n");
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

    write("xml_xpath_parser_ast.log", output.data);
}

unittest  // XPathParser.selectNodes
{
    debug(debug_pham_xml_xml_xpath) nodeIndent = 0;

    auto doc = new XmlDocument!string().load(bookStoreXml);
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

unittest // fctBoolean - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "boolean(1)");
    assert(r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "boolean(0)");
    assert(!r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "boolean(-0)");
    assert(!r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "boolean(2.5)");
    assert(r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "boolean('test')");
    assert(r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "boolean('')");
    assert(!r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "false()");
    assert(!r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "not(false())");
    assert(r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "true()");
    assert(r.get!bool(), r.get!string());

    r = evaluate(doc.documentElement, "not(true())");
    assert(!r.get!bool(), r.get!string());
}

unittest // fctNumber - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "number(1)");
    assert(r.get!double() == 1, r.get!string());

    r = evaluate(doc.documentElement, "number(0.11)");
    assert(r.get!double() == 0.11, r.get!string());

    r = evaluate(doc.documentElement, "number(-0)");
    assert(r.get!double() == 0, r.get!string());

    r = evaluate(doc.documentElement, "number(-1.11)");
    assert(r.get!double() == -1.11, r.get!string());

    r = evaluate(doc.documentElement, "number(+0)");
    assert(r.get!double() == 0, r.get!string());

    r = evaluate(doc.documentElement, "number('NotANumber')");
    assert(r.get!double().isNaN, r.get!string());
}

unittest // fctCeiling - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "ceiling(2.9)");
    assert(cast(long)r.get!double() == 3, r.get!string());

    r = evaluate(doc.documentElement, "ceiling(2.1)");
    assert(cast(long)r.get!double() == 3, r.get!string());

    r = evaluate(doc.documentElement, "ceiling(0.1)");
    assert(cast(long)r.get!double() == 1, r.get!string());

    r = evaluate(doc.documentElement, "ceiling(-2.9)");
    assert(cast(long)r.get!double() == -2, r.get!string());
}

unittest // fctRound - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "round(2.9)");
    assert(cast(long)r.get!double() == 3, r.get!string());

    r = evaluate(doc.documentElement, "round(2.1)");
    assert(cast(long)r.get!double() == 2, r.get!string());

    r = evaluate(doc.documentElement, "round(2.5)");
    assert(cast(long)r.get!double() == 3, r.get!string());

    r = evaluate(doc.documentElement, "round(-2.5)");
    assert(cast(long)r.get!double() == -2, r.get!string());
}

unittest // fctFloor - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "floor(2.9)");
    assert(cast(long)r.get!double() == 2, r.get!string());

    r = evaluate(doc.documentElement, "floor(2.1)");
    assert(cast(long)r.get!double() == 2, r.get!string());

    r = evaluate(doc.documentElement, "floor(0.9)");
    assert(cast(long)r.get!double() == 0, r.get!string());

    r = evaluate(doc.documentElement, "floor(-2.9)");
    assert(cast(long)r.get!double() == -3, r.get!string());
}

unittest // fctString - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "string(1)");
    assert(r.get!string() == "1", r.get!string());

    r = evaluate(doc.documentElement, "string(-0)");
    assert(r.get!string() == "0", r.get!string());

    r = evaluate(doc.documentElement, "string(+0)");
    assert(r.get!string() == "0", r.get!string());

    r = evaluate(doc.documentElement, "string(+0)");
    assert(r.get!string() == "0", r.get!string());

    r = evaluate(doc.documentElement, "string(false())");
    assert(r.get!string() == "false", r.get!string());

    r = evaluate(doc.documentElement, "string(true())");
    assert(r.get!string() == "true", r.get!string());
}

unittest // fctConcate - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "concat('Ab', 'Ab')");
    assert(r.get!string() == "AbAb", r.get!string());

    r = evaluate(doc.documentElement, "concat('Ab', 'CC', 'Ab')");
    assert(r.get!string() == "AbCCAb", r.get!string());
}

unittest // fctStartWith - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "starts-with('AABB', 'AA')");
    assert(r.get!bool() == true, r.get!string());

    r = evaluate(doc.documentElement, "starts-with('AABB', 'BB')");
    assert(r.get!bool() == false, r.get!string());
}

unittest // fctContains - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "contains('AABBCC', 'BB')");
    assert(r.get!bool() == true, r.get!string());

    r = evaluate(doc.documentElement, "contains('AABBCC', 'DD')");
    assert(r.get!bool() == false, r.get!string());
}

unittest // fctSubstringBefore - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "substring-before('AA/BB', '/')");
    assert(r.get!string() == "AA", r.get!string());

    r = evaluate(doc.documentElement, "substring-before('AA/BB', 'D')");
    assert(r.get!string() == "", r.get!string());
}

unittest // fctSubstringAfter - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "substring-after('AA/BB', '/')");
    assert(r.get!string() == "BB", r.get!string());

    r = evaluate(doc.documentElement, "substring-after('AA/BB', 'D')");
    assert(r.get!string() == "", r.get!string());
}

unittest // fctSubstring - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "substring('ABC', 2)");
    assert(r.get!string() == "BC", r.get!string());

    r = evaluate(doc.documentElement, "substring('ABCD', 2, 2)");
    assert(r.get!string() == "BC", r.get!string());

    r = evaluate(doc.documentElement, "substring('ABCDE', 1.5, 2.6)");
    assert(r.get!string() == "BCD", r.get!string());

    r = evaluate(doc.documentElement, "substring('ABCDE', 0, 3)");
    assert(r.get!string() == "AB", r.get!string());

    r = evaluate(doc.documentElement, "substring('ABCDE', 0 div 0, 3)");
    assert(r.get!string() == "", r.get!string());

    r = evaluate(doc.documentElement, "substring('ABCDE', 0, 0 div 0)");
    assert(r.get!string() == "", r.get!string());

    r = evaluate(doc.documentElement, "substring('ABCDE', -42, 1 div 0)");
    assert(r.get!string() == "ABCDE", r.get!string());

    r = evaluate(doc.documentElement, "substring('ABCDE', -1 div 0, 1 div 0)");
    assert(r.get!string() == "", r.get!string());

    r = evaluate(doc.documentElement, "string-length('ABCDE')");
    assert(r.get!double() == 5, r.get!string());

    r = evaluate(doc.documentElement, "string-length('')");
    assert(r.get!double() == 0, r.get!string());
}

unittest // fctNormalizeSpace - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "normalize-space('')");
    assert(r.get!string() == "", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space(' \t\n\r')");
    assert(r.get!string() == "", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space(' \t\n\r')");
    assert(r.get!string() == "", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space('A ')");
    assert(r.get!string() == "A", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space('A    ')");
    assert(r.get!string() == "A", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space(' A')");
    assert(r.get!string() == "A", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space('    A')");
    assert(r.get!string() == "A", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space(' A ')");
    assert(r.get!string() == "A", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space('   A   ')");
    assert(r.get!string() == "A", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space('A B')");
    assert(r.get!string() == "A B", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space('A    B')");
    assert(r.get!string() == "A B", text('"', r.get!string(), '"'));

    r = evaluate(doc.documentElement, "normalize-space('   AB    CD   ')");
    assert(r.get!string() == "AB CD", text('"', r.get!string(), '"'));
}

unittest // fctTranslate - Simple
{
    auto doc = new XmlDocument!string().load(dummyXml);

    auto r = evaluate(doc.documentElement, "translate('', 'abc', 'ABC')");
    assert(r.get!string() == "", r.get!string());

    r = evaluate(doc.documentElement, "translate('abc', 'abc', 'ABC')");
    assert(r.get!string() == "ABC", r.get!string());

    r = evaluate(doc.documentElement, "translate('abc', '', 'XYZ')");
    assert(r.get!string() == "abc", r.get!string());

    r = evaluate(doc.documentElement, "translate('abc', 'abca', 'ABCZ')");
    assert(r.get!string() == "ABC", r.get!string());

    r = evaluate(doc.documentElement, "translate('aba', 'b', 'B')");
    assert(r.get!string() == "aBa", r.get!string());

}

unittest // fctString - Complex
{
    auto doc = loadUnittestXml("auction.xml");
    if (doc is null)
        return;

    auto r = evaluate(doc.documentElement, "string((//*:Open)[1])");
    assert(r.get!string() == "2000-03-21:07:41:34-05:00", r.get!string());
}
