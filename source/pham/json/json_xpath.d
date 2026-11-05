/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

/* Overview over XPath vs JSONPath
XPath 	JSONPath 	        Description
/ 	    $ 	                the document object/element
. 	    @ 	                the current object/element
/ 	    . or [] 	        child operator
.. 	    n/a 	            parent operator
// 	    .. 	                nested descendants. JSONPath borrows this syntax from E4X.
* 	    * 	                wildCard. All objects/elements regardless of their names.
@ 	    n/a 	            attribute access. JSON data items don't have attributes.
[] 	    [] 	                subscript operator. XPath uses it to iterate over element collections and for predicates. In JavaScript and JSON it is the native array operator.
| 	    [,] 	            Union operator in XPath results in a combination of node sets. JSONPath allows alternate names or array indices as a set.
n/a 	[start:end:step] 	array slice operator borrowed from ES4.
[] 	    ?() 	            applies a filter (script) expression.
n/a 	() 	                script expression, using the underlying script engine.
() 	    n/a 	            grouping in Xpath
*/

module pham.json.json_xpath;

import std.conv : to;
import std.math : isInfinity, isNaN;
import std.math.operations : isClose;
import std.math.traits : signbit;

debug(debug_pham_json_json_xpath) import std.stdio : writeln;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_array_dictionary;
import pham.utl.utl_utf8;
import pham.json.json_exception;
import pham.json.json_type;
import pham.json.json_value;

@safe:

/**
 * Returns first node of matching xpath expression
 * Params:
 *  root = a context/root node to search from
 *  xpath = a xpath expression string
 * Returns:
 *  a value, JSONValue, of matching xpath expression or JSONValue.null if no matching found
 */
JSONValue selectNode(JSONValue root, string xpath)
{
    return selectNode(root, root, xpath);
}

/**
 * Returns first node of matching xpath expression
 * Params:
 *  root = the root node of json
 *  source = a context node to search from
 *  xpath = a xpath expression string
 * Returns:
 *  a value, JSONValue, of matching xpath expression or JSONValue.null if no matching found
 */
JSONValue selectNode(ref JSONValue root, JSONValue source, string xpath)
{
    auto resultList = selectNodes(root, source, xpath);
    return resultList.length ? resultList[0] : JSONValue.init;
}

/**
 * Returns node-list of matching xpath expression
 * Params:
 *  root = a context/root node to search from
 *  xpath = a xpath expression string
 * Returns:
 *     a node-list, XmlNodeList, of matching xpath expression
 */
JSONValue[] selectNodes(JSONValue root, string xpath)
{
    return selectNodes(root, root, xpath);
}

/**
 * Returns node-list of matching xpath expression
 * Params:
 *  root = the root node of json
 *  source = a context node to search from
 *  xpath = a xpath expression string
 * Returns:
 *     a node-list, XmlNodeList, of matching xpath expression
 */
JSONValue[] selectNodes(ref JSONValue root, JSONValue source, string xpath)
{
    auto context = XPathContext(XPathJSONValue(root), XPathJSONValue(source));
    return selectNodes(context, xpath);
}

/// ditto
JSONValue[] selectNodes(XPathContext context, string xpath)
{
    auto engine = new XPathQuery(context);
    auto vNodes = engine.query(xpath);
    if (vNodes.length == 0)
        return null;

    JSONValue[] result;
    result.reserve(vNodes.length);
    foreach (ref n; vNodes)
        result ~= n.value;
    return result;
}

alias selectSingleNode = selectNode;

struct XPathContext
{
@safe:

public:
    this(XPathJSONValue rootNode, XPathJSONValue contextNode) nothrow
    {
        this.rootNode = rootNode;
        if (contextNode.isValue)
            this.contextNodes = [contextNode];
    }

	XPathValue getVariable(string name)
	{
        auto result = name in variables;
        if (result is null)
            throw new JSONException("Undefined variable $" ~ name);
		return *result;
	}

	void setVariable(string name, XPathValue value)
	{
		variables[name] = value;
	}

    pragma(inline, true)
    @property XPathJSONValue* hasContextNode() nothrow return
    {
        return contextNodes.length != 0 && contextNodes[0].isValue
            ? &contextNodes[0]
            : null;
    }

    pragma(inline, true)
    @property XPathJSONValue* hasRootNode() nothrow return
    {
        return rootNode.isValue ? &rootNode : null;
    }

public:
    static int compareNumber(double left, double right) nothrow @safe
    {
        return isClose(left, right)
            ? 0
            : (left > right ? 1 : -1);
    }

    static int compareStringCase(string left, string right) nothrow @safe
    {
        import std.algorithm.comparison : cmp;

        return cmp(left, right);
    }

    static int compareStringCaseInsentive(string left, string right) nothrow @safe
    {
        import std.uni : sicmp;

        return sicmp(left, right);
    }

    static bool equalNameCase(string left, string right) nothrow @safe
    {
        return left == right;
    }

    static bool equalNameCaseInsentive(string left, string right) nothrow @safe
    {
        import std.uni : sicmp;

        return sicmp(left, right) == 0;
    }

    static bool toBoolean(double value) nothrow @safe
    {
        return !isNaN(value) && !isClose(value, 0.0);
    }

    static double toNumber(string value) nothrow @safe
    {
        try
            return toNumberImpl(value);
        catch (Exception)
            return double.nan;
    }

    static double toNumberImpl(string value) @safe
    {
        import std.string : strip;

         value = value.strip();

         return value == JSONLiteral.nnan
            ? -double.nan
            : (value == JSONLiteral.pnan
                ? double.nan
                : (value == JSONLiteral.ninf
                    ? -double.infinity
                    : (value == JSONLiteral.pinf
                        ? double.infinity
                        : value.to!double())));
    }

    static long toLongImpl(string value) @safe
    {
        import std.string : strip;

         value = value.strip();

         return value == JSONLiteral.nnan || value == JSONLiteral.pnan || value == JSONLiteral.ninf
            ? long.min
            : (value == JSONLiteral.pinf
                ? long.max
                : cast(long)(value.to!double()));
    }

    static string toString(double value) nothrow @safe
    {
        try
            return value.isNaN()
                ? (value.signbit() ? JSONLiteral.nnan : JSONLiteral.pnan)
                : (value.isInfinity()
                    ? (value.signbit() ? JSONLiteral.ninf : JSONLiteral.pinf)
                    : (isClose(value, 0.0) ? "0.0" : value.to!string()));
        catch (Exception)
            return JSONLiteral.pnan;
    }

public:
    XPathJSONValue rootNode;
    XPathJSONValue[] contextNodes;
	//size_t position = 1;   /// 1-based
	//size_t size = 1;   /// 1-based
	//FunctionRegistry functions; //todo
    Dictionary!(string, XPathValue) variables;

    int function(double left, double right) nothrow @safe compareNumberFct = &compareNumber;
    int function(string left, string right) nothrow @safe compareStringFct = &compareStringCase;
    bool function(string left, string right) nothrow @safe equalNameFct = &equalNameCase;
}

struct XPathJSONValue
{
public:
	this(JSONValue value,
        JSONValue parent = JSONValue.init) nothrow
	{
		this.value = value;
        this.parent = parent;
	}

    bool opEqual(scope const(XPathJSONValue) rhs) const nothrow
    {
        return value.xpathInfo.opEqual(rhs.xpathInfo);
    }

	final bool asBoolean() const nothrow
	{
		final switch (value.type)
		{
            case JSONType.false_:
                return false;
            case JSONType.true_:
                return true;
            case JSONType.integer:
                return value.intImpl != 0;
            case JSONType.float_:
                return XPathContext.toBoolean(value.fltImpl);
            case JSONType.string:
                return value.strImpl.length > 0;
            case JSONType.object:
            case JSONType.array:
                return value.length > 0;
            case JSONType.null_:
                return false;
		}
	}

	final double asNumber() const
	{
		final switch (value.type)
		{
            case JSONType.integer:
                return value.intImpl;
            case JSONType.float_:
                return value.fltImpl;
            case JSONType.false_:
                return 0.0;
            case JSONType.true_:
                return 1.0;
            case JSONType.string:
                return XPathContext.toNumber(value.strImpl);
            case JSONType.object:
            case JSONType.array:
                return XPathContext.toNumber(asString());
            case JSONType.null_:
                return 0.0;
		}
	}

	final string asString() const
	{
		final switch (value.type)
		{
            case JSONType.string:
                return value.strImpl;
            case JSONType.false_:
                return JSONLiteral.false_;
            case JSONType.true_:
                return JSONLiteral.true_;
            case JSONType.integer:
                return value.intImpl.to!string();
            case JSONType.float_:
                return XPathContext.toString(value.fltImpl);
            case JSONType.object:
            case JSONType.array:
                // XPath string-value of element = concat of descendant text;
                // for JSON we concatenate child string-values.
                Appender!string result;
                foreach (i; 0..value.length)
                    result.put(XPathJSONValue(value[i]).asString());
                return result.data;
            case JSONType.null_:
                return null;
		}
	}

	final JSONValue asJSONValue() nothrow
	{
		return value;
	}

    size_t toHash() const nothrow
    {
        return value.xpathInfo.toHash();
    }

	string toString() const
	{
        import std.conv : text;

        const xpathInfo = value.xpathInfo;
		return text("XPathJSONValue(type=", value.type, ", name=", value.name, ", index=", xpathInfo.index, ", level=", xpathInfo.level, ")");
	}

    pragma(inline, true)
    @property bool hasParent() const nothrow
    {
        const type = parent.type;
        return type == JSONType.object || type == JSONType.array;
    }

    pragma(inline, true)
    @property bool isParent() const nothrow
    {
        const type = value.type;
        return type == JSONType.object || type == JSONType.array;
    }

    pragma(inline, true)
    @property bool isValue() const nothrow
    {
        return !value.isNull || hasParent;
    }

public:
	JSONValue value;     /// underlying JSON
	JSONValue parent;
    alias this = value;
}

struct XPathValue
{
@safe:
    enum Type : ubyte
    {
        null_,
        boolean,
        number,
        string,
        jsons,
    }

public:
    this(string value) nothrow
    {
        this._string = value;
        this._type = Type.string;
    }

    this(double value) nothrow
    {
        this._number = value;
        this._type = Type.number;
    }

    this(bool value) nothrow
    {
        this._boolean = value;
        this._type = Type.boolean;
    }

    this(XPathJSONValue[] value) nothrow
    {
        this._jsons = value;
        this._type = Type.jsons;
    }

    bool asBoolean() const nothrow
    {
        final switch(type)
        {
            case Type.boolean:
                return _boolean;
            case Type.number:
                return XPathContext.toBoolean(_number);
            case Type.string:
                return _string.length > 0;
            case Type.jsons:
                return _jsons.length > 0;
            case Type.null_:
                return false;
        }
    }

    XPathJSONValue[] asJsons() nothrow
    {
        return _type == Type.jsons ? _jsons : null;
        /*
        final switch(type)
        {
            case Type.jsons:
                return _jsons;
            case Type.boolean:
                return [XPathJSONValue(JSONValue(_boolean))];
            case Type.number:
                return [XPathJSONValue(JSONValue(_number))];
            case Type.string:
                return [XPathJSONValue(JSONValue(_string))];
            case Type.null_:
                return null;
        }
        */
    }

    double asNumber() const
    {
        final switch(type)
        {
            case Type.number:
                return _number;
            case Type.boolean:
                return _boolean ? 1.0 : 0.0;
            case Type.string:
                return XPathContext.toNumber(_string);
            case Type.jsons:
                return XPathContext.toNumber(asString());
            case Type.null_:
                return double.nan;
        }
    }

    string asString() const
    {
        final switch(type)
        {
            case Type.string:
                return _string;
            case Type.boolean:
                return _boolean ? JSONLiteral.true_ : JSONLiteral.false_;
            case Type.number:
                return XPathContext.toString(_number);
            case Type.jsons:
                Appender!string result;
                foreach (e; _jsons)
                    result.put(e.asString());
                return result.data;
            case Type.null_:
                return null;
        }
    }

    static XPathValue emptyJsons() nothrow
    {
        XPathValue result;
        result._type = Type.jsons;
        return result;
    }

    void unionJsons(XPathJSONValue[] values)
    {
        assert(_type == Type.null_ || _type == Type.jsons);

        _type = Type.jsons;

        auto duplicates = Dictionary!(XPathJSONValue, bool)(_jsons.length + values.length + 100);
        foreach (ref n; _jsons)
            duplicates[n] = true;

        foreach (ref n; values)
        {
            if (n in duplicates)
                continue;

            duplicates[n] = true;
            _jsons ~= n;
        }
    }

    pragma(inline, true)
    @property bool canBeNumber() const nothrow
    {
        return type == Type.number
            || type == Type.boolean;
    }

    pragma(inline, true)
    @property Type type() const nothrow
    {
        return _type;
    }

private:
    string _string;
    double _number = 0;
    XPathJSONValue[] _jsons;
    bool _boolean;
    Type _type;
}

struct XPathToken
{
    enum Type : ubyte
    {
        eof,                // Must be first member
        lParen,             /// (
        rParen,             /// )
        lBracket,           /// [
        rBracket,           /// ]
        dollar,             /// $ => root
        at,                 /// @ => current
        sDot,               /// .
        dDot,               /// ..
        comma,              /// , => union separator inside [] or argument separator
        pipe,               /// | => path union
        colon,              /// : => slice separator
        question,           /// ? => filter introducer
        bang,               /// ! => not
        eq,                 /// ==
        ne,                 /// !=
        lt,                 /// <
        le,                 /// <=
        gt,                 /// >
        ge,                 /// >=
        plus,               /// +
        minus,              /// -
        star,               /// * => multiply
        slash,              /// / => divide
        percent,            /// % => mod
        and,                /// && => and
        or,                 /// || => or
        string,             /// quoted string literal
        number,             /// numeric literal
        identifier,         /// identifier, true, false, null, not, and, or, mod until parser classifies
        variable,           /// $variable-name
        error,              /// unterminated string literal
    }

public:
    string toString() const
    {
        import std.conv : text;

		return text("XPathToken(text=", value, ", startIndex=", startIndex, ", type=", type, ")");
    }

public:
    string value;
    size_t startIndex;
    Type type;
}

struct XPathLexer
{
    import std.ascii : isAlpha, isAlphaNum, isDigit, isWhite;

nothrow @safe:

public:
    this(string expr)
    {
        debug(debug_pham_json_json_xpath) debug writeln(__FUNCTION__,  "(expr=", expr, ")");

        this.expr = expr;
        this.indexExpr = 0;
    }

    XPathToken[] tokenize()
    {
        XPathToken[] tokens;

        while (indexExpr < expr.length)
        {
            skipWhitespace();

            if (indexExpr >= expr.length)
                break;

            auto token = nextToken();
            tokens ~= token;
        }

        if (indexExpr < expr.length)
        {
            tokens ~= XPathToken(expr[indexExpr..$], indexExpr, XPathToken.Type.error);
            indexExpr = expr.length;
        }

        return tokens;
    }

    XPathToken nextToken()
    {
        const startIndex = indexExpr;
        UTF8Iterator ch = void;
        if (!nextUTF8Char(expr, indexExpr, ch))
            return XPathToken(null, indexExpr, XPathToken.Type.eof);

        if (ch.code == '(')
            return XPathToken("(", startIndex, XPathToken.Type.lParen);

        if (ch.code == ')')
            return XPathToken(")", startIndex, XPathToken.Type.rParen);

        if (ch.code == '[')
            return XPathToken("[", startIndex, XPathToken.Type.lBracket);

        if (ch.code == ']')
            return XPathToken("]", startIndex, XPathToken.Type.rBracket);

        if (ch.code == '@')
            return XPathToken("@", startIndex, XPathToken.Type.at);

        if (ch.code == ',')
            return XPathToken(",", startIndex, XPathToken.Type.comma);

        if (ch.code == ':')
            return XPathToken(":", startIndex, XPathToken.Type.colon);

        if (ch.code == '?')
            return XPathToken("?", startIndex, XPathToken.Type.question);

        if (ch.code == '+')
            return XPathToken("+", startIndex, XPathToken.Type.plus);

        if (ch.code == '-')
            return XPathToken("-", startIndex, XPathToken.Type.minus);

        if (ch.code == '*')
            return XPathToken("*", startIndex, XPathToken.Type.star);

        if (ch.code == '/')
            return XPathToken("/", startIndex, XPathToken.Type.slash);

        if (ch.code == '%')
            return XPathToken("%", startIndex, XPathToken.Type.percent);

        if (ch.code == '$')
        {
            if (nextCharIs(&isIdentifierStart))
            {
                auto identifier = parseIdentifier(startIndex);
                return XPathToken(identifier.value, identifier.startIndex, XPathToken.Type.variable);
            }
            else
                return XPathToken("$", startIndex, XPathToken.Type.dollar);
        }

        if (ch.code == '.')
        {
            if (nextCharIs('.'))
                return XPathToken("..", startIndex, XPathToken.Type.dDot);

            if (nextCharIs(&isDigit))
                return parseNumber(startIndex);

            return XPathToken(".", startIndex, XPathToken.Type.sDot);
        }

        if (ch.code == '=')
        {
            if (nextCharIs('='))
                return XPathToken("=", startIndex, XPathToken.Type.eq);
        }

        if (ch.code == '&')
        {
            if (nextCharIs('&'))
                return XPathToken("&&", startIndex, XPathToken.Type.and);
        }

        if (ch.code == '|')
        {
            return nextCharIs('|')
                ? XPathToken("||", startIndex, XPathToken.Type.or)
                : XPathToken("|", startIndex, XPathToken.Type.pipe);
        }

        if (ch.code == '!')
        {
            return nextCharIs('=')
                ? XPathToken("!=", startIndex, XPathToken.Type.ne)
                : XPathToken("!", startIndex, XPathToken.Type.bang);
        }

        if (ch.code == '<')
        {
            return nextCharIs('=')
                ? XPathToken("<=", startIndex, XPathToken.Type.le)
                : XPathToken("<", startIndex, XPathToken.Type.lt);
        }

        if (ch.code == '>')
        {
            return nextCharIs('=')
                ? XPathToken(">=", startIndex, XPathToken.Type.ge)
                : XPathToken(">", startIndex, XPathToken.Type.gt);
        }

        if (ch.code == '"' || ch.code == '\'')
            return parseString(startIndex, ch.code);

        if (isDigit(ch.code))
            return parseNumber(startIndex);

        if (isIdentifierStart(ch.code))
            return parseIdentifier(startIndex);

        return XPathToken("Unexpected character: " ~ ch.utfValue().idup, startIndex, XPathToken.Type.error);
    }

    ref typeof(this) rewind() return
    {
        indexExpr = 0;
        return this;
    }

private:
    XPathToken parseIdentifier(const(size_t) startIndex)
    {
        size_t endPos = indexExpr;

        UTF8Iterator ch;
        while (nextUTF8Char(expr, indexExpr, ch))
        {
            if (isIdentifierChar(ch.code))
            {
                endPos += ch.count;
            }
            else
            {
                indexExpr -= ch.count;
                break;
            }
        }

        return XPathToken(expr[startIndex..endPos], startIndex, XPathToken.Type.identifier);
    }

    XPathToken parseNumber(const(size_t) startIndex)
    {
        size_t endPos = indexExpr;

        UTF8Iterator ch;

        while (nextUTF8Char(expr, indexExpr, ch) && isDigit(ch.code))
        {
            endPos += ch.count;
        }
        indexExpr -= ch.count;

        if (nextUTF8Char(expr, indexExpr, ch) && ch.code == '.')
        {
            endPos += ch.count;
            while (nextUTF8Char(expr, indexExpr, ch) && isDigit(ch.code))
            {
                endPos += ch.count;
            }
            indexExpr -= ch.count;
        }
        else
            indexExpr -= ch.count;

        return XPathToken(expr[startIndex..endPos], startIndex, XPathToken.Type.number);
    }

    XPathToken parseString(const(size_t) startIndex, const(dchar) quote)
    {
        debug(debug_pham_json_json_xpath) debug writeln(__FUNCTION__,  "()");

        string value;
        size_t endPos = indexExpr;

        UTF8Iterator ch;
        while (nextUTF8Char(expr, indexExpr, ch))
        {
            if (ch.code == quote)
                break;

            //debug(debug_pham_json_json_xpath) debug writeln("\t", "ch=", ch, ", indexExpr=", indexExpr);

            if (ch.code == '\\' && indexExpr + 1 < expr.length)
            {
                debug(debug_pham_json_json_xpath) debug writeln("\t", "value=", value, ", indexExpr=", indexExpr, ", endPos=", endPos);

                if (endPos != 0)
                {
                    value = expr[startIndex + 1..endPos];
                    endPos = 0;
                }

                if (nextUTF8Char(expr, indexExpr, ch))
                    value ~= ch.utfValue();

                ch = UTF8Iterator.init;
            }
            else
            {
                if (endPos == 0)
                    value ~= ch.utfValue();
                else
                    endPos += ch.count;
            }
        }

        // string literal without quote chars
        if (endPos != 0)
            value = expr[startIndex + 1..endPos];

        return ch.code == quote
            ? XPathToken(value, startIndex, XPathToken.Type.string)
            : XPathToken("Unterminated string literal: " ~ value, startIndex, XPathToken.Type.error);
    }

    pragma(inline, true)
	static bool isIdentifierChar(dchar c)// @nogc pure
	{
		return c == '_' || isAlphaNum(c);
	}

    pragma(inline, true)
	static bool isIdentifierStart(dchar c)// @nogc pure
	{
		return c == '_' || isAlpha(c);
	}

    pragma(inline, true)
    bool nextCharIs(const(dchar) c)
    {
        UTF8Iterator ch;
        const result = nextUTF8Char(expr, indexExpr, ch) && ch.code == c;
        if (!result)
            indexExpr -= ch.count;
        return result;
    }

    alias NextCharIsCheck = bool function(dchar) nothrow @safe;
    pragma(inline, true)
    bool nextCharIs(scope NextCharIsCheck c)
    {
        UTF8Iterator ch;
        const result = nextUTF8Char(expr, indexExpr, ch) && c(ch.code);
        if (!result)
            indexExpr -= ch.count;
        return result;
    }

    void skipWhitespace()
    {
        while (indexExpr < expr.length && isWhite(expr[indexExpr]))
            indexExpr++;
    }

private:
    string expr;
    size_t indexExpr;
}

abstract class XPathASTNode
{
public:
    final XPathValue evaluate(ref XPathContext queryContext)
    {
        return _evaluateFct ? _evaluateFct(queryContext) : XPathValue.init;
    }

    abstract void astOutput(ref Appender!string buffer, size_t indent) const @safe;

    override string toString() const @safe
    {
        Appender!string buffer;
        astOutput(buffer, 0);
        return buffer.data;
    }

protected:
    static long normalize(long index, const(long) length) nothrow pure @safe
    {
        if (index < 0)
            index += length;

        return index < 0
            ? 0
            : (index > length ? length : index);
    }

    static void astOutputIndent(ref Appender!string buffer, size_t indent) nothrow @safe
    {
        while (indent--)
        {
            buffer.put("  ");
        }
    }

protected:
    alias XPathEvaluate = XPathValue delegate(ref XPathContext queryContext);
    XPathEvaluate _evaluateFct;
}

abstract class XPathAxisNode : XPathASTNode
{
protected:
    static XPathJSONValue[] getChildren(ref XPathJSONValue node) nothrow
    {
        XPathJSONValue[] result;

        if (node.type == JSONType.object)
        {
            auto nodeObject = node.objectImpl;
            foreach (key, ref childValue; nodeObject)
            {
                result ~= XPathJSONValue(childValue, node.value);
            }
        }
        else if (node.type == JSONType.array)
        {
            auto nodeArray = node.arrayImpl;
            foreach (ref childValue; nodeArray)
            {
                result ~= XPathJSONValue(childValue, node.value);
            }
        }

        return result;
    }

    static XPathJSONValue[] getDescendants(ref XPathJSONValue node) nothrow
    {
        XPathJSONValue[] result;

        if (node.type == JSONType.object)
        {
            auto nodeObject = node.objectImpl;
            foreach (key, ref childValue; nodeObject)
            {
                auto nodeValue = XPathJSONValue(childValue, node.value);
                result ~= nodeValue;
                if (childValue.length > 0)
                    result ~= getDescendants(nodeValue);
            }
        }
        else if (node.type == JSONType.array)
        {
            auto nodeArray = node.arrayImpl;
            foreach (ref childValue; nodeArray)
            {
                auto nodeValue = XPathJSONValue(childValue, node.value);
                result ~= nodeValue;
                if (childValue.length > 0)
                    result ~= getDescendants(nodeValue);
            }
        }

        return result;
    }

    static XPathJSONValue[] uniqueNodes(XPathJSONValue[] nodes) nothrow
    {
        if (nodes.length == 0)
            return nodes;

        XPathJSONValue[] result;
        result.reserve(nodes.length);
        auto duplicates = Dictionary!(XPathJSONValue, bool)(nodes.length + 100);
        foreach (ref node; nodes)
        {
            if (node in duplicates)
                continue;

            result ~= node;
            duplicates[node] = true;
        }
        return result;
    }
}

/// Top-level query: one or more paths joined by `|` (union).
class XPathQueryNode : XPathAxisNode
{
public:
    this(XPathPathNode[] paths) nothrow @safe
    {
        this.paths = paths;
        this._evaluateFct = &evaluateQUERY;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        astOutputIndent(buffer, indent);
        buffer.put("XPathQueryNode()").put("\n");
        foreach (path; paths)
            path.astOutput(buffer, indent + 1);
    }

public:
    XPathPathNode[] paths;

protected:
    final XPathValue evaluateQUERY(ref XPathContext queryContext)
    {
        auto result = XPathValue.emptyJsons();
        foreach(path; paths)
        {
            auto v = path.evaluate(queryContext);
            result.unionJsons(v.asJsons());
        }
        return result;
    }
}

class XPathPathNode : XPathAxisNode
{
    enum Anchor : ubyte
    {
        none,    /// relative (used inside some contexts)
        current, /// @
        root,    /// $
    }

public:
    this(Anchor anchor, XPathSegmentNode[] segments) nothrow @safe
    {
        this.anchor = anchor;
        this.segments = segments;
        this._evaluateFct = &evaluatePATH;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathPathNode(anchor=", anchor, ")")).put("\n");
        foreach (segment; segments)
            segment.astOutput(buffer, indent + 1);
    }

public:
    XPathSegmentNode[] segments;
    Anchor anchor;

protected:
    final XPathValue evaluatePATH(ref XPathContext queryContext)
    {
        XPathContext segmentContext = queryContext;

        final switch (anchor)
        {
            case Anchor.none:
            case Anchor.current:
                auto contextNode = queryContext.hasContextNode;
                segmentContext.contextNodes = contextNode !is null
                    ? [*contextNode]
                    : null;
                break;
            case Anchor.root:
                auto rootNode = queryContext.hasRootNode;
                segmentContext.contextNodes = rootNode !is null
                    ? [*rootNode]
                    : null;
                break;
        }

        foreach (segment; segments)
        {
            auto v = segment.evaluate(segmentContext);
            segmentContext.contextNodes = v.asJsons();
        }

        return XPathValue(segmentContext.contextNodes);
    }
}

abstract class XPathSegmentNode : XPathAxisNode
{
    bool descendant; /// true when introduced by `..`
}

/// `.name`, `.*`, `..name`, `..*`
class XPathMemberSegmentNode : XPathSegmentNode
{
public:
    this(bool descendant, string name, bool wildCard) nothrow @safe
    {
        this.descendant = descendant;
        this.name = name;
        this.wildCard = wildCard;
        this._evaluateFct = &evaluateMEMBER;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathMemberSegmentNode(descendant=", descendant, ", wildCard=", wildCard, ", name=", name, ")")).put("\n");
    }

public:
    string name;     /// empty when wildCard
    bool wildCard;

protected:
    final XPathValue evaluateMEMBER(ref XPathContext queryContext)
    {
        XPathJSONValue[] result;
        foreach (ref contextNode; queryContext.contextNodes)
        {
            auto candidates = descendant ? getDescendants(contextNode) : getChildren(contextNode);
            if (wildCard)
                result ~= candidates;
            else
            {
                foreach (candidate; candidates)
                {
                    if (queryContext.equalNameFct(candidate.name, name))
                        result ~= candidate;
                }
            }
        }
        return XPathValue(uniqueNodes(result));
    }
}

/// Bracket segment containing one or more selectors (comma = union).
class XPathBracketSegmentNode : XPathSegmentNode
{
public:
    this(XPathSelectorNode[] selectors) nothrow @safe
    {
        this.selectors = selectors;
        this._evaluateFct = &evaluateSELECTORS;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathBracketSegmentNode(descendant=", descendant, ")")).put("\n");
        foreach (selector; selectors)
            selector.astOutput(buffer, indent + 1);
    }

public:
    XPathSelectorNode[] selectors;

protected:
    final XPathValue evaluateSELECTORS(ref XPathContext queryContext)
    {
        XPathContext selectorContext = queryContext;
        auto result = XPathValue.emptyJsons();
        foreach (ref contextNode; queryContext.contextNodes)
        {
            XPathJSONValue[] baseNodes = [contextNode];
            if (descendant)
                baseNodes ~= getDescendants(contextNode);

            foreach (baseNode; baseNodes)
            {
                foreach (selector; selectors)
                {
                    selectorContext.contextNodes = [baseNode];
                    auto v = selector.evaluate(selectorContext);
                    result.unionJsons(v.asJsons());
                }
            }
        }
        return result;
    }
}

abstract class XPathSelectorNode : XPathAxisNode
{
}

class XPathNameSelectorNode : XPathSelectorNode
{
public:
    this(string name) nothrow @safe
    {
        this.name = name;
        this._evaluateFct = &evaluateSELECTOR;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathNameSelectorNode(name=", name, ")")).put("\n");
    }

public:
    string name;

protected:
    final XPathValue evaluateSELECTOR(ref XPathContext queryContext)
    {
        auto contextNode = queryContext.hasContextNode;
        if (contextNode is null)
            return XPathValue.init;

        XPathJSONValue[] result;
        auto nodes = getChildren(*contextNode);
        foreach (ref node; nodes)
        {
            if (queryContext.equalNameFct(node.name, name))
                result ~= node;
        }
        return XPathValue(result);
    }
}

class XPathIndexSelectorNode : XPathSelectorNode
{
public:
    this(long index) nothrow @safe
    {
        this.index = index;
        this._evaluateFct = &evaluateSELECTOR;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathIndexSelectorNode(index=", index, ")")).put("\n");
    }

public:
    long index;

protected:
    final XPathValue evaluateSELECTOR(ref XPathContext queryContext)
    {
        auto contextNode = queryContext.hasContextNode;
        if (contextNode is null)
            return XPathValue.init;

        auto nodes = getChildren(*contextNode);
        const nodesLength = cast(long)nodes.length;

        const long i = index < 0
            ? nodesLength + index
            : index;

        return i >= 0 && i < nodesLength
            ? XPathValue([nodes[cast(size_t)i]])
            : XPathValue.init;
    }
}

class XPathSliceSelectorNode : XPathSelectorNode
{
public:
    this(long begin, long end, long step, bool hasBegin, bool hasEnd, bool hasStep) nothrow @safe
    {
        this.begin = begin;
        this.end = end;
        this.step = step;
        this.hasBegin = hasBegin;
        this.hasEnd = hasEnd;
        this.hasStep = hasStep;
        this._evaluateFct = &evaluateSELECTOR;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathSliceSelectorNode(begin=", begin, ", end=", end, ", step=", step, ", hasBegin=", hasBegin, ", hasEnd=", hasEnd, ", hasStep=", hasStep, ")")).put("\n");
    }

public:
    long begin;
    long end;
    long step;
    bool hasBegin;
    bool hasEnd;
    bool hasStep;

protected:
    final XPathValue evaluateSELECTOR(ref XPathContext queryContext)
    {
        auto contextNode = queryContext.hasContextNode;
        if (contextNode is null)
            return XPathValue.init;

        if (this.step == 0)
            return XPathValue.init;

        auto nodes = getChildren(*contextNode);
        const nodesLength = cast(long)nodes.length;
        if (nodesLength == 0)
            return XPathValue.init;

        XPathJSONValue[] result;
        if (this.step > 0)
        {
            const long eBegin = this.hasBegin ? normalize(this.begin, nodesLength) : 0;
            const long eEnd = this.hasEnd ? normalize(this.end, nodesLength) : nodesLength;
            for (long i = eBegin; i < eEnd; i += this.step)
            {
                if (i >= 0 && i < nodesLength)
                    result ~= nodes[cast(size_t)i];
            }
        }
        else
        {
            const long eBegin = this.hasBegin ? normalize(this.begin, nodesLength) : nodesLength - 1;
            const long eEnd = this.hasEnd ? normalize(this.end, nodesLength) : -1; // exclusive sentinel for reverse
            for (long i = eBegin; i > eEnd; i += this.step)
            {
                if (i >= 0 && i < nodesLength)
                    result ~= nodes[cast(size_t)i];
            }
        }
        return XPathValue(result);
    }
}

class XPathWildCardSelectorNode : XPathSelectorNode
{
public:
    this() nothrow @safe
    {
        this._evaluateFct = &evaluateSELECTOR;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathWildCardSelectorNode()")).put("\n");
    }

protected:
    final XPathValue evaluateSELECTOR(ref XPathContext queryContext)
    {
        auto contextNode = queryContext.hasContextNode;
        return contextNode !is null
            ? XPathValue(getChildren(*contextNode))
            : XPathValue.init;
    }
}

class XPathFilterSelectorNode : XPathSelectorNode
{
public:
    this(XPathExpressionNode expr) nothrow @safe
    {
        this.expr = expr;
        this._evaluateFct = &evaluateSELECTOR;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathFilterSelectorNode()")).put("\n");
        expr.astOutput(buffer, indent + 1);
    }

public:
    XPathExpressionNode expr;

protected:
    final XPathValue evaluateSELECTOR(ref XPathContext queryContext)
    {
        auto contextNode = queryContext.hasContextNode;
        if (contextNode is null)
            return XPathValue.init;

        XPathContext exprContext = queryContext;
        XPathJSONValue[] result;
        auto nodes = getChildren(*contextNode);
        foreach (ref node; nodes)
        {
            exprContext.contextNodes = [node];
            auto v = expr.evaluate(exprContext);
            if (v.asBoolean())
                result ~= node;
        }
        return XPathValue(result);
    }
}

abstract class XPathExpressionNode : XPathASTNode
{
}

class XPathBinaryNode : XPathExpressionNode
{
    enum Operator : ubyte
    {
        eq,   /// =
        ne,   /// !=
        lt,   /// <
        le,   /// <=
        gt,   /// >
        ge,   /// >=
        add,  /// +
        sub,  /// -
        mul,  /// *
        div,  /// /
        mod,  /// %
        and,  /// &&
        or,   /// ||
    }

public:
    this(Operator operator, XPathExpressionNode left, XPathExpressionNode right) nothrow
    {
        this._operator = operator;
        this.left = left;
        this.right = right;

        final switch(operator)
        {
            case Operator.eq:
                this._evaluateFct = &evaluateEQ;
                break;
            case Operator.ne:
                this._evaluateFct = &evaluateNE;
                break;
            case Operator.lt:
                this._evaluateFct = &evaluateLT;
                break;
            case Operator.le:
                this._evaluateFct = &evaluateLE;
                break;
            case Operator.gt:
                this._evaluateFct = &evaluateGT;
                break;
            case Operator.ge:
                this._evaluateFct = &evaluateGE;
                break;
            case Operator.add:
                this._evaluateFct = &evaluateADD;
                break;
            case Operator.sub:
                this._evaluateFct = &evaluateSUB;
                break;
            case Operator.mul:
                this._evaluateFct = &evaluateMUL;
                break;
            case Operator.div:
                this._evaluateFct = &evaluateDIV;
                break;
            case Operator.mod:
                this._evaluateFct = &evaluateMOD;
                break;
            case Operator.and:
                this._evaluateFct = &evaluateAND;
                break;
            case Operator.or:
                this._evaluateFct = &evaluateOR;
                break;
        }
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathBinaryNode(operator=", operator, ")")).put("\n");
        left.astOutput(buffer, indent + 1);
        right.astOutput(buffer, indent + 1);
    }

    pragma(inline, true)
    @property final Operator operator() const nothrow
    {
        return _operator;
    }

public:
    XPathExpressionNode left;
    XPathExpressionNode right;

protected:
    final XPathValue evaluateEQ(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        return XPathValue(evaluateLogicalEqual(vLeft, vRight, queryContext));
    }

    final XPathValue evaluateNE(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        return XPathValue(!evaluateLogicalEqual(vLeft, vRight, queryContext));
    }

    final XPathValue evaluateLT(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        if (evaluateLogicalByNumber(vLeft, vRight))
            return XPathValue(queryContext.compareNumberFct(vLeft.asNumber(), vRight.asNumber()) < 0);
        else
            return XPathValue(queryContext.compareStringFct(vLeft.asString(), vRight.asString()) < 0);
    }

    final XPathValue evaluateLE(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        if (evaluateLogicalByNumber(vLeft, vRight))
            return XPathValue(queryContext.compareNumberFct(vLeft.asNumber(), vRight.asNumber()) <= 0);
        else
            return XPathValue(queryContext.compareStringFct(vLeft.asString(), vRight.asString()) <= 0);
    }

    final XPathValue evaluateGT(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        if (evaluateLogicalByNumber(vLeft, vRight))
            return XPathValue(queryContext.compareNumberFct(vLeft.asNumber(), vRight.asNumber()) > 0);
        else
            return XPathValue(queryContext.compareStringFct(vLeft.asString(), vRight.asString()) > 0);
    }

    final XPathValue evaluateGE(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        if (evaluateLogicalByNumber(vLeft, vRight))
            return XPathValue(queryContext.compareNumberFct(vLeft.asNumber(), vRight.asNumber()) >= 0);
        else
            return XPathValue(queryContext.compareStringFct(vLeft.asString(), vRight.asString()) >= 0);
    }

    final XPathValue evaluateADD(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        return XPathValue(vLeft.asNumber() + vRight.asNumber());
    }

    final XPathValue evaluateSUB(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        return XPathValue(vLeft.asNumber() - vRight.asNumber());
    }

    final XPathValue evaluateMUL(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        return XPathValue(vLeft.asNumber() * vRight.asNumber());
    }

    final XPathValue evaluateDIV(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        const vRightValue = vRight.asNumber();
        return queryContext.compareNumberFct(vRightValue, 0.0) != 0
            ? XPathValue(vLeft.asNumber() / vRightValue)
            : XPathValue(double.nan);
    }

    final XPathValue evaluateMOD(ref XPathContext queryContext)
    {
        import std.math : fmod;

        auto vLeft = left.evaluate(queryContext);
        auto vRight = right.evaluate(queryContext);
        const vRightValue = vRight.asNumber();
        return queryContext.compareNumberFct(vRightValue, 0.0) != 0
            ? XPathValue(fmod(vLeft.asNumber(), vRightValue))
            : XPathValue(double.nan);
    }

    final XPathValue evaluateAND(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        if (!vLeft.asBoolean())
            return XPathValue(false);
        auto vRight = right.evaluate(queryContext);
        return XPathValue(vRight.asBoolean());
    }

    final XPathValue evaluateOR(ref XPathContext queryContext)
    {
        auto vLeft = left.evaluate(queryContext);
        if (vLeft.asBoolean())
            return XPathValue(true);
        auto vRight = right.evaluate(queryContext);
        return XPathValue(vRight.asBoolean());
    }

    static bool evaluateLogicalEqual(scope ref XPathValue left, scope ref XPathValue right, ref XPathContext queryContext)
    {
        // Simplified XPath 1.0 equality rules
        if (left.type == XPathValue.Type.jsons)
        {
            if (right.type == XPathValue.Type.jsons)
            {
                foreach (a; left.asJsons())
                {
                    foreach (b; right.asJsons())
                    {
                        if (queryContext.compareStringFct(a.asString(), b.asString()) == 0)
                            return true;
                    }
                }
                return false;
            }
            else
            {
                foreach (a; left.asJsons())
                {
                    if (right.type == XPathValue.Type.boolean && a.asBoolean() == right.asBoolean)
                        return true;
                    if (right.type == XPathValue.Type.number && queryContext.compareNumberFct(a.asNumber(), right.asNumber()) == 0)
                        return true;
                    if (right.type == XPathValue.Type.string && queryContext.compareStringFct(a.asString(), right.asString()) == 0)
                        return true;
                }
                return false;
            }
        }

        if (right.type == XPathValue.Type.jsons)
            return evaluateLogicalEqual(right, left, queryContext);
        else if (evaluateLogicalByNumber(left, right))
            return queryContext.compareNumberFct(left.asNumber(), right.asNumber()) == 0;
        else
            return queryContext.compareStringFct(left.asString(), right.asString()) == 0;
    }

    pragma(inline, true)
    static bool evaluateLogicalByNumber(scope ref XPathValue left, scope ref XPathValue right) nothrow
    {
        return left.canBeNumber || right.canBeNumber;
    }

private:
    Operator _operator;
}

class XPathUnaryNode : XPathExpressionNode
{
    enum Operator : ubyte
    {
        not,                // not
        minus,              // -
        plus,               // +
    }

public:
    this(Operator operator, XPathExpressionNode expr) nothrow
    {
        this._operator = operator;
        this.expr = expr;

        final switch (operator)
        {
            case Operator.not:
                this._evaluateFct = &evaluateNOT;
                break;
            case Operator.minus:
                this._evaluateFct = &evaluateMINUS;
                break;
            case Operator.plus:
                this._evaluateFct = &evaluatePLUS;
                break;
        }
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathUnaryNode(operator=", operator, ")")).put("\n");
        expr.astOutput(buffer, indent + 1);
    }

    pragma(inline, true)
    @property final Operator operator() const nothrow
    {
        return _operator;
    }

public:
    XPathExpressionNode expr;

protected:
    final XPathValue evaluatePLUS(ref XPathContext queryContext)
    {
        auto v = expr.evaluate(queryContext);
        return XPathValue(v.asNumber());
    }

    final XPathValue evaluateMINUS(ref XPathContext queryContext)
    {
        auto v = expr.evaluate(queryContext);
        return XPathValue(v.asNumber() * -1);
    }

    final XPathValue evaluateNOT(ref XPathContext queryContext)
    {
        auto v = expr.evaluate(queryContext);
        return XPathValue(!v.asBoolean());
    }

private:
    Operator _operator;
}

class XPathExpressionPathNode : XPathExpressionNode
{
public:
    this(XPathPathNode path) nothrow @safe
    {
        this.path = path;
        this._evaluateFct = &evaluatePATH;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathExpressionPathNode()")).put("\n");
        path.astOutput(buffer, indent + 1);
    }

public:
    XPathPathNode path;

protected:
    final XPathValue evaluatePATH(ref XPathContext queryContext)
    {
        return path.evaluate(queryContext);
    }
}

class XPathLiteralNode : XPathExpressionNode
{
@safe:

public:
    this() nothrow
    {
        this._evaluateFct = &evaluateValue;
    }

    this(string value) nothrow
    {
        this.value = XPathValue(value);
        this._evaluateFct = &evaluateValue;
    }

    this(double value) nothrow
    {
        this.value = XPathValue(value);
        this._evaluateFct = &evaluateValue;
    }

    this(bool value) nothrow
    {
        this.value = XPathValue(value);
        this._evaluateFct = &evaluateValue;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathLiteralNode(value=", value.asString(), ")")).put("\n");
    }

public:
    XPathValue value;

protected:
    final XPathValue evaluateValue(ref XPathContext queryContext) nothrow
    {
        return value;
    }
}

class XPathVariableNode : XPathExpressionNode
{
public:
    this(string name) nothrow
    {
        this.name = name;
        this._evaluateFct = &evaluateVARIABLE;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathVariableNode(name=", name, ")")).put("\n");
    }

public:
    string name;

protected:
    final XPathValue evaluateVARIABLE(ref XPathContext queryContext)
    {
        return queryContext.getVariable(name);
    }
}

class XPathFunctionCallNode : XPathExpressionNode
{
public:
    this(string name, XPathExpressionNode[] arguments) nothrow @safe
    {
        this.name = name;
        this.arguments = arguments;
        this._evaluateFct = &evaluateFUNCTION;
    }

    override void astOutput(ref Appender!string buffer, size_t indent) const @safe
    {
        import std.conv : text;

        astOutputIndent(buffer, indent);
        buffer.put(text("XPathFunctionCallNode(name=", name, ")")).put("\n");
        foreach (argument; arguments)
            argument.astOutput(buffer, indent + 1);
    }

public:
    string name;
    XPathExpressionNode[] arguments;

protected:
    final XPathValue evaluateFUNCTION(ref XPathContext queryContext)
    {
        //todo
        return queryContext.getVariable(name);
    }
}

struct XPathParser
{
@safe:

public:
    this(XPathToken[] tokens) nothrow
    {
        this.tokens = tokens;
        this.tokenIndex = 0;
    }

    XPathQueryNode parse()
    {
        XPathPathNode[] paths;
        paths ~= parsePath();
        while (match(XPathToken.Type.pipe))
            paths ~= parsePath();

        if (current.type != XPathToken.Type.eof)
            throw new JSONParserException("Unexpected token " ~ current.toString() ~ " at end of expression");

        return new XPathQueryNode(paths);
    }

    static XPathQueryNode parse(string xpath)
    {
        auto lexer = XPathLexer(xpath);
        auto tokens = lexer.tokenize();
        auto parser = XPathParser(tokens);
        return parser.parse();
    }

private:
    XPathPathNode parsePath()
    {
        XPathPathNode.Anchor anchor;
        switch (match([XPathToken.Type.dollar, XPathToken.Type.at]))
        {
            case 0:
                anchor = XPathPathNode.Anchor.root;
                break;
            case 1:
                anchor = XPathPathNode.Anchor.current;
                break;
            default:
                anchor = XPathPathNode.Anchor.none;
                break;
        }

        XPathSegmentNode[] segments;
        auto currentType = current.type;
        while (currentType == XPathToken.Type.sDot
                || currentType == XPathToken.Type.dDot
                || currentType == XPathToken.Type.lBracket)
        {
            segments ~= parseSegment();
            currentType = current.type;
        }

        // Bare `$` or `@` is valid; a completely empty path is only ok as relative `@` body edge case
        if (anchor == XPathPathNode.Anchor.none && segments.length == 0)
            throw new JSONXPathException("Expect path segment but " ~ current.toString());

        return new XPathPathNode(anchor, segments);
    }

    XPathSegmentNode parseSegment()
    {
        if (match(XPathToken.Type.dDot))
        {
            if (current.type == XPathToken.Type.lBracket)
            {
                auto br = parseBracket();
                br.descendant = true;
                return br;
            }

            bool descendant = true;
            string name = null;
            bool wildCard = false;

            if (match(XPathToken.Type.star))
                wildCard = true;
            else
                name = expect(XPathToken.Type.identifier); // "name after '..'");

            return new XPathMemberSegmentNode(descendant, name, wildCard);
        }

        if (match(XPathToken.Type.sDot))
        {
            bool descendant = false;
            string name = null;
            bool wildCard = false;

            if (match(XPathToken.Type.star))
                wildCard = true;
            else
                name = expect(XPathToken.Type.identifier); // "name after '.'");

            return new XPathMemberSegmentNode(descendant, name, wildCard);
        }

        if (current.type == XPathToken.Type.lBracket)
            return parseBracket();

        throw new JSONXPathException("Expected path segment but " ~ current.toString());
    }

    XPathBracketSegmentNode parseBracket()
    {
        expect(XPathToken.Type.lBracket); //, "'['");
        XPathSelectorNode[] selectors;
        selectors ~= parseSelector();
        while (match(XPathToken.Type.comma))
            selectors ~= parseSelector();
        expect(XPathToken.Type.rBracket); //, "']'");
        return new XPathBracketSegmentNode(selectors);
    }

    XPathSelectorNode parseSelector()
    {
        switch (match([XPathToken.Type.star, XPathToken.Type.question]))
        {
            case 0:
                return new XPathWildCardSelectorNode();

            case 1:
                expect(XPathToken.Type.lParen); //, "'(' after '?'");
                auto fl = new XPathFilterSelectorNode(parseOr());
                expect(XPathToken.Type.rParen); //, "')' after filter");
                return fl;

            default:
                break;
        }

        const currentType = current.type;
        if (currentType == XPathToken.Type.string)
        {
            auto name = current.value;
            advance();
            return new XPathNameSelectorNode(name);
        }
        else if (currentType == XPathToken.Type.identifier)
        {
            // unquoted name inside brackets (common extension)
            auto name = current.value;
            advance();
            return new XPathNameSelectorNode(name);
        }
        // number, slice, or signed index
        else if (currentType == XPathToken.Type.number
                || currentType == XPathToken.Type.colon
                || currentType == XPathToken.Type.minus)
            return parseIndexOrSlice();

        throw new JSONXPathException("Expected selector but " ~ current.toString());
    }

    XPathSelectorNode parseIndexOrSlice()
    {
        // Detect slice if a colon appears in the selector before comma/rBracket
        bool looksLikeSlice = false;
        {
            int depth = 0;
            size_t i = tokenIndex;
            while (i < tokens.length)
            {
                const k = tokens[i].type;
                if (k == XPathToken.Type.lParen)
                    depth++;
                else if (k == XPathToken.Type.rParen)
                    depth--;
                else if (depth == 0 && k == XPathToken.Type.colon)
                {
                    looksLikeSlice = true;
                    break;
                }
                else if (depth == 0 && (k == XPathToken.Type.comma || k == XPathToken.Type.rBracket))
                    break;
                i++;
            }
        }

        if (!looksLikeSlice)
        {
            return new XPathIndexSelectorNode(parseLong());
        }

        long begin, end, step = 1;
        bool hasBegin, hasEnd, hasStep;

        if (current.type != XPathToken.Type.colon)
        {
            hasBegin = true;
            begin = parseLong();
        }
        expect(XPathToken.Type.colon); // "':' in slice");
        auto currentType = current.type;
        if (currentType != XPathToken.Type.colon
            && currentType != XPathToken.Type.comma
            && currentType != XPathToken.Type.rBracket)
        {
            hasEnd = true;
            end = parseLong();
        }
        if (match(XPathToken.Type.colon))
        {
            currentType = current.type;
            if (currentType != XPathToken.Type.comma
                && currentType != XPathToken.Type.rBracket)
            {
                hasStep = true;
                step = parseLong();
                if (step == 0)
                    throw new JSONXPathException("Slice step must not be 0");
            }
        }

        return new XPathSliceSelectorNode(begin, end, step, hasBegin, hasEnd, hasStep);
    }

    long parseLong()
    {
        const neg = match(XPathToken.Type.minus);
        auto numberText = expect(XPathToken.Type.number);
        const v = XPathContext.toLongImpl(numberText);
        return neg ? -v : v;
    }

    XPathExpressionNode parseOr()
    {
        auto left = parseAnd();
        while (match(XPathToken.Type.or) || match(XPathToken.Type.identifier, "or"))
        {
            auto b = new XPathBinaryNode(XPathBinaryNode.Operator.or, left, parseAnd());
            left = b;
        }
        return left;
    }

    XPathExpressionNode parseAnd()
    {
        auto left = parseEquality();
        while (match(XPathToken.Type.and) || match(XPathToken.Type.identifier, "and"))
        {
            auto b = new XPathBinaryNode(XPathBinaryNode.Operator.and, left, parseEquality());
            left = b;
        }
        return left;
    }

	XPathExpressionNode parseEquality()
	{
        auto left = parseRelational();
        while (true)
        {
            XPathBinaryNode b;
            switch (match([XPathToken.Type.eq, XPathToken.Type.ne]))
            {
                case 0:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.eq, left, parseRelational());
                    break;
                case 1:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.ne, left, parseRelational());
                    break;
                default:
                    return left;
            }
            left = b;
        }
        return left;
	}

	XPathExpressionNode parseRelational()
	{
        auto left = parseAdditive();
        while (true)
        {
            XPathBinaryNode b;
            switch (match([XPathToken.Type.lt, XPathToken.Type.le, XPathToken.Type.gt, XPathToken.Type.ge]))
            {
                case 0:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.lt, left, parseAdditive());
                    break;
                case 1:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.le, left, parseAdditive());
                    break;
                case 2:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.gt, left, parseAdditive());
                    break;
                case 3:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.ge, left, parseAdditive());
                    break;
                default:
                    return left;
            }
            left = b;
        }
        return left;
	}

    XPathExpressionNode parseAdditive()
    {
        auto left = parseMultiplicative();
        while (true)
        {
            XPathExpressionNode b;
            switch (match([XPathToken.Type.plus, XPathToken.Type.minus]))
            {
                case 0:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.add, left, parseMultiplicative());
                    break;
                case 1:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.sub, left, parseMultiplicative());
                    break;
                default:
                    return left;
            }
            left = b;
        }
        return left;
    }

    XPathExpressionNode parseMultiplicative()
    {
        auto left = parseUnary();
        while (true)
        {
            XPathExpressionNode b;
            switch (match([XPathToken.Type.star, XPathToken.Type.slash, XPathToken.Type.percent]))
            {
                case 0:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.mul, left, parseUnary());
                    break;
                case 1:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.div, left, parseUnary());
                    break;
                case 2:
                    b = new XPathBinaryNode(XPathBinaryNode.Operator.mod, left, parseUnary());
                    break;
                default:
                    return left;
            }
            left = b;
        }
        return left;
    }

    XPathExpressionNode parseUnary()
    {
        switch (match([XPathToken.Type.bang, XPathToken.Type.minus, XPathToken.Type.plus]))
        {
            case 0:
                return new XPathUnaryNode(XPathUnaryNode.Operator.not, parseUnary());
            case 1:
                // Prefer folding into literal number when possible
                if (current.type == XPathToken.Type.number)
                {
                    const number = current.value.to!double();
                    advance();
                    return new XPathLiteralNode(-number);
                }
                return new XPathUnaryNode(XPathUnaryNode.Operator.minus, parseUnary());
            case 2:
                return new XPathUnaryNode(XPathUnaryNode.Operator.plus, parseUnary());
            default:
                return parsePrimary();
        }
    }

    XPathExpressionNode parsePrimary()
    {
        switch (current.type)
        {
            case XPathToken.Type.lParen:
                advance();
                auto e = parseOr();
                expect(XPathToken.Type.rParen); //, "')'");
                return e;

            case XPathToken.Type.string:
                auto text = current.value;
                advance();
                return new XPathLiteralNode(text);

            case XPathToken.Type.number:
                auto number = current.value.to!double();
                advance();
                return new XPathLiteralNode(number);

            case XPathToken.Type.identifier:
                const text = current.value;
                if (text == "null")
                {
                    advance();
                    return new XPathLiteralNode();
                }
                else if (text == "true" || text == "false")
                {
                    advance();
                    return new XPathLiteralNode(text == "true");
                }

                // function call: name(...)
                if (next.type == XPathToken.Type.lParen)
                    return parseFunctionCall();

                throw new JSONXPathException("Unexpected name '" ~ current.toString() ~ "' in expression");

            case XPathToken.Type.dollar:
            case XPathToken.Type.at:
                return new XPathExpressionPathNode(parsePath());

            default:
                break;
        }

        throw new JSONXPathException("Unexpected token in expression: " ~ current.toString());
    }

	XPathFunctionCallNode parseFunctionCall()
	{
        const functionName = expect(XPathToken.Type.identifier);
		expect(XPathToken.Type.lParen);
		XPathExpressionNode[] args;
		if (current.type != XPathToken.Type.rParen)
		{
			args ~= parseOr();
			while (match(XPathToken.Type.comma))
				args ~= parseOr();
		}
		expect(XPathToken.Type.rParen);
		return new XPathFunctionCallNode(functionName, args);
	}

    pragma(inline, true)
    void advance() nothrow
    {
        tokenIndex++;
    }

    pragma(inline, true)
    string expect(const(XPathToken.Type) type)
    {
        if (current.type != type)
            throw new JSONXPathException("Unexpected token: " ~ current.toString() ~ "; expected token type: " ~ type.stringof);

        auto result = current.value;
        advance();
        return result;
    }

    pragma(inline, true)
    bool match(const(XPathToken.Type) type) nothrow
    {
        if (current.type == type)
        {
            advance();
            return true;
        }

        return false;
    }

    pragma(inline, true)
    bool match(const(XPathToken.Type) type, string value) nothrow
    {
        auto t = current;
        if (t.type == type && t.value == value)
        {
            advance();
            return true;
        }

        return false;
    }

    ptrdiff_t match(const(XPathToken.Type)[] types) nothrow
    {
        const currentType = current.type;
        foreach (i, type; types)
        {
            if (currentType == type)
            {
                advance();
                return i;
            }
        }

        return -1;
    }

    pragma(inline, true)
    @property XPathToken current() nothrow
    {
        return tokenIndex < tokens.length
            ? tokens[tokenIndex]
            : XPathToken.init;
    }

    pragma(inline, true)
    @property XPathToken next() nothrow
    {
        return tokenIndex + 1 < tokens.length
            ? tokens[tokenIndex + 1]
            : XPathToken.init;
    }

private:
    XPathToken[] tokens;
    size_t tokenIndex;
}

struct XPathQuery
{
public:
    this(XPathContext queryContext)
    {
        this.queryContext = queryContext;
    }

    XPathJSONValue[] query(string xpath)
    {
        auto path = XPathParser.parse(xpath);
        auto v = path.evaluate(queryContext);
        return v.type == XPathValue.Type.jsons
            ? v.asJsons()
            : null;
    }

private:

private:
    XPathContext queryContext;
}

unittest // XPathLexer
{
auto t1 = q"JSON
$.document.child[@attr=='value']
JSON";
    auto lexer = XPathLexer(t1);
    auto tokens = lexer.tokenize();
    //debug(debug_pham_json_json_xpath) debug writeln(__LINE__, " ", tokens);
    assert(tokens.length == 11, tokens.length.to!string() ~ "?" ~ tokens.to!string());
    assert(tokens[0].type == XPathToken.Type.dollar);
    assert(tokens[1].type == XPathToken.Type.sDot);
    assert(tokens[2].type == XPathToken.Type.identifier);
    assert(tokens[2].value == "document", tokens[2].toString());
    assert(tokens[3].type == XPathToken.Type.sDot);
    assert(tokens[4].type == XPathToken.Type.identifier);
    assert(tokens[4].value == "child", tokens[4].toString());
    assert(tokens[5].type == XPathToken.Type.lBracket);
    assert(tokens[6].type == XPathToken.Type.at);
    assert(tokens[7].type == XPathToken.Type.identifier);
    assert(tokens[7].value == "attr", tokens[7].toString());
    assert(tokens[8].type == XPathToken.Type.eq);
    assert(tokens[9].type == XPathToken.Type.string);
    assert(tokens[9].value == "value", tokens[9].toString());
    assert(tokens[10].type == XPathToken.Type.rBracket);

auto t2 = q"JSON
$.document.child[@attr=='val\'ue']
JSON";
    lexer = XPathLexer(t2);
    tokens = lexer.tokenize();
    //debug(debug_pham_json_json_xpath) debug writeln(__LINE__, " ", tokens);
    assert(tokens.length == 11, tokens.length.to!string() ~ "?" ~ tokens.to!string());
    assert(tokens[0].type == XPathToken.Type.dollar);
    assert(tokens[1].type == XPathToken.Type.sDot);
    assert(tokens[2].type == XPathToken.Type.identifier);
    assert(tokens[2].value == "document", tokens[2].toString());
    assert(tokens[3].type == XPathToken.Type.sDot);
    assert(tokens[4].type == XPathToken.Type.identifier);
    assert(tokens[4].value == "child", tokens[4].toString());
    assert(tokens[5].type == XPathToken.Type.lBracket);
    assert(tokens[6].type == XPathToken.Type.at);
    assert(tokens[7].type == XPathToken.Type.identifier);
    assert(tokens[7].value == "attr", tokens[7].toString());
    assert(tokens[8].type == XPathToken.Type.eq);
    assert(tokens[9].type == XPathToken.Type.string);
    assert(tokens[9].value == "val'ue", tokens[9].toString());
    assert(tokens[10].type == XPathToken.Type.rBracket);
}

unittest // XPathLexer
{
auto t1 = q"JSON
$.document.child[@attr=='value]
JSON";

    auto lexer = XPathLexer(t1);
    auto tokens = lexer.tokenize();
    //debug(debug_pham_json_json_xpath) debug writeln(__LINE__, " ", tokens);
    assert(tokens.length == 10, tokens.length.to!string() ~ "?" ~ tokens.to!string());
    assert(tokens[9].type == XPathToken.Type.error);
    assert(tokens[9].value == "Unterminated string literal: value]\n", tokens[9].toString());
}

unittest // XPathParser
{
    //import std.conv : text;

    static immutable string expected =
q"TXT
XPathQueryNode()
  XPathPathNode(anchor=root)
    XPathMemberSegmentNode(descendant=false, wildCard=false, name=document)
    XPathMemberSegmentNode(descendant=false, wildCard=false, name=child)
TXT";

    auto ast = XPathParser.parse("$.document.child");
    Appender!string buffer;
    ast.astOutput(buffer, 0);
    //debug(debug_pham_json_json_xpath) debug writeln(__LINE__, " ", buffer.data);
    assert(buffer.data == expected, '"' ~ buffer.data ~ '"');
}

unittest // XPathQuery
{
    import pham.json.json_reader : parseJSON;

    auto data = parseJSON(`{
        "document": {
            "child": {
                "value": 42
            }
        }
    }`);

    auto root = XPathJSONValue(data);
    auto context = XPathContext(root, root);
    auto engine = new XPathQuery(context);
    auto result = engine.query("$.document.child");
    //debug(debug_pham_json_json_xpath) debug writeln(__LINE__, " ", result);
    assert(result.length == 1);
    assert(result[0]["value"].integer == 42);

    auto select = selectNode(root, "$.document.child");
    assert(select.type == JSONType.object);
    assert(select["value"].integer == 42);
}
