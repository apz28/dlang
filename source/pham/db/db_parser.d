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

module pham.db.parser;

import std.array : Appender;
import std.uni : isAlphaNum, isSpace;

version (unittest) import pham.utl.test;
import pham.utl.utf8 : nextUTF8Char;
import pham.db.type : uint32;

nothrow @safe:

enum DbTokenKind : ubyte
{
    space,
    comment,
    parameterUnnamed,
    parameterNamed,
    quotedDouble,
    quotedSingle,
    quotedBracket,
    literal,
}

// S should be either 'const(char)[]' or 'string'
struct DbTokenizer(S)
{
nothrow @safe:

public:
    dchar replacementChar = dchar.max;

public:
    this(S sql) pure
    {
        this._sql = sql;
        this._empty = sql.length == 0;
        if (sql.length)
            this.popFront();
    }

    static S parseParameter(S sql, void delegate(ref Appender!S result, S parameterName, uint32 parameterNumber) nothrow @safe parameterCallBack)
    in
    {
        assert(parameterCallBack !is null);
    }
    do
    {
        version (TraceFunction) traceFunction!("pham.db.database")("sql.length=", sql.length);

        if (sql.length == 0)
            return sql;

        size_t prevP, beginP;
        uint32 parameterNumber; // Based 1 value
        auto result = Appender!S();
        auto tokenizer = DbTokenizer!S(sql);
        while (!tokenizer.empty)
        {
            //import pham.utl.test; dgWriteln("tokenizer.kind=", tokenizer.kind, ", tokenizer.front=", tokenizer.front);

            final switch (tokenizer.kind)
            {
                case DbTokenKind.parameterUnnamed:
                case DbTokenKind.parameterNamed:
                    // Leading text before parameter?
                    if (beginP < prevP)
                    {
                        //import pham.utl.test; dgWriteln("sql[beginP..prevP]=", sql[beginP..prevP]);

                        result.put(sql[beginP..prevP]);
                    }

                    // save info for next round
                    beginP = tokenizer.offset;

                    parameterCallBack(result, tokenizer.front, ++parameterNumber);
                    break;

                case DbTokenKind.space:
                case DbTokenKind.comment:
                case DbTokenKind.quotedDouble:
                case DbTokenKind.quotedSingle:
                case DbTokenKind.quotedBracket:
                case DbTokenKind.literal:
                    break;
            }

            prevP = tokenizer.offset;
            tokenizer.popFront();
        }

        //import pham.utl.test; dgWriteln("tokenizer.kind=", tokenizer.kind, ", tokenizer.front=", tokenizer.front, ", parameterNumber=", parameterNumber);

        if (parameterNumber == 0)
            return sql;
        else
        {
            // Remaining text?
            if (beginP < sql.length)
            {
                //import pham.utl.test; dgWriteln("sql[beginP..$]=", sql[beginP..$]);

                result.put(sql[beginP..$]);
            }

            return result.data;
        }
    }

    void popFront() pure
    {
        _currentParameterIndicator = [];
        _malformed = false;
        _beginP = _p;

        if (_p >= _sql.length)
        {
            _empty = true;
            _currentToken = [];
            _kind = DbTokenKind.space;
            return;
        }

        void literalToken()
        {
            _currentToken = _sql[_beginP.._p];
            _kind = DbTokenKind.literal;
        }

        const c = readChar();
        final switch (charKind(c))
        {
            case CharKind.space:
                _currentToken = readSpace();
                _kind = DbTokenKind.space;
                return;

            case CharKind.parameterUnnamed:
                _currentParameterIndicator = _sql[_beginP.._p];
                _currentToken = [];
                _kind = DbTokenKind.parameterUnnamed;
                return;

            case CharKind.parameterNamed:
                _currentParameterIndicator = _sql[_beginP.._p];
                if (_p < _sql.length)
                {
                    const parameter2P = _p;
                    if (isNameChar(readChar()))
                    {
                        _beginP = parameter2P;
                        _currentToken = readName();
                        _kind = DbTokenKind.parameterNamed;
                        return;
                    }
                    else
                        _p = parameter2P;
                }
                _malformed = true;
                _currentToken = _currentParameterIndicator;
                _kind = DbTokenKind.literal;
                return;

            case CharKind.quotedDouble:
                _currentToken = readQuoted(c);
                _kind = DbTokenKind.quotedDouble;
                return;

            case CharKind.quotedSingle:
                _currentToken = readQuoted(c);
                _kind = DbTokenKind.quotedSingle;
                return;

            case CharKind.quotedBracket:
                _currentToken = readQuoted(']');
                _kind = DbTokenKind.quotedBracket;
                return;

            case CharKind.commentSingle:
                if (_p < _sql.length)
                {
                    const commentSingleP = _p;
                    if (readChar() == c)
                    {
                        _currentToken = readCommentSingle();
                        _kind = DbTokenKind.comment;
                        return;
                    }
                    else
                        _p = commentSingleP;
                }
                return literalToken();

            case CharKind.commentMulti:
                if (_p < _sql.length)
                {
                    const commentMultiP = _p;
                    if (readChar() == '*')
                    {
                        _currentToken = readCommentMulti();
                        _kind = DbTokenKind.comment;
                        return;
                    }
                    else
                        _p = commentMultiP;
                }
                return literalToken();

            case CharKind.literal:
                _currentToken = readLiteral();
                _kind = DbTokenKind.literal;
                return literalToken();
        }
    }

    void reset()
    {
        _p = _beginP = 0;
        _currentToken, _currentParameterIndicator = null;
        _kind = DbTokenKind.space;
        _malformed = false;
        _empty = _sql.length == 0;
        if (_sql.length)
            popFront();
    }

    pragma(inline, true)
    @property bool empty() const @nogc pure
    {
        return _empty;
    }

    @property S front() const @nogc pure
    {
        return _currentToken;
    }

    @property bool malformed() const @nogc pure
    {
        return _malformed;
    }

    @property DbTokenKind kind() const @nogc pure
    {
        return _kind;
    }

    @property size_t offset() const @nogc pure
    {
        return _p;
    }

    @property S parameterIndicator() const pure
    {
        return _currentParameterIndicator;
    }

    @property S sql() const pure
    {
        return _sql;
    }

private:
    enum CharKind : ubyte
    {
        space,
        parameterUnnamed,
        parameterNamed,
        quotedDouble,
        quotedSingle,
        quotedBracket,
        commentSingle,
        commentMulti,
        literal,
    }

    static CharKind charKind(const(dchar) c) @nogc pure
    {
        switch (c)
        {
            case '?':
                return CharKind.parameterUnnamed;
            case '@':
            case ':':
                return CharKind.parameterNamed;
            case '`':
            case '\'':
                return CharKind.quotedSingle;
            case '"':
                return CharKind.quotedDouble;
            case '[':
                return CharKind.quotedBracket;
            case '-':
            case '#':
                return CharKind.commentSingle;
            case '/':
                return CharKind.commentMulti;
            default:
                return isSpaceChar(c) ? CharKind.space : CharKind.literal;
        }
    }

    static bool isNameChar(const(dchar) c) @nogc pure
    {
        //import pham.utl.test; dgWriteln("c=", c, ", isAlphaNum(c)=", isAlphaNum(c));

        return c == '_' || c == '$' || isAlphaNum(c);
    }

    static bool isSpaceChar(const(dchar) c) @nogc pure
    {
        return c == '\n' || c == '\r' || c == '\t' || isSpace(c);
    }

    pragma(inline, true)
    dchar readChar() @nogc pure
    {
        dchar cCode;
        ubyte cCount;
        if (!nextUTF8Char(_sql, _p, cCode, cCount))
            cCode = replacementChar;
        _p += cCount;
        return cCode;
    }

    S readCommentMulti() pure
    {
        dchar prevC = 0;
        while (_p < _sql.length)
        {
            const c = readChar();
            if (c == '/' && prevC == '*')
                return _sql[_beginP.._p];
            prevC = c;
        }

        _malformed = true;
        return _sql[_beginP.._p];
    }

    S readCommentSingle() pure
    {
        while (_p < _sql.length)
        {
            const c = readChar();
            if (c == 0x0A)
                return _sql[_beginP.._p];
            else if (c == 0x0D)
            {
                // Skip return line feed?
                if (_p < _sql.length)
                {
                    const saveP = _p;
                    if (readChar() != 0x0A)
                        _p = saveP;
                }
                return _sql[_beginP.._p];
            }
        }
        return _sql[_beginP.._p];
    }

    S readLiteral() pure
    {
        while (_p < _sql.length)
        {
            const saveP = _p;
            if (charKind(readChar()) != CharKind.literal)
            {
                _p = saveP;
                break;
            }
        }
        return _sql[_beginP.._p];
    }

    S readName() pure
    {
        //import pham.utl.test; dgWriteln("_beginP=", _beginP, ", _sql=", _sql[_beginP.._p]);

        while (_p < _sql.length)
        {
            const saveP = _p;
            if (!isNameChar(readChar()))
            {
                _p = saveP;
                break;
            }
        }
        return _sql[_beginP.._p];
    }

    S readQuoted(const(dchar) endQuotedChar) pure
    {
        bool escaped;
        while (_p < _sql.length)
        {
            const c = readChar();
            if (c == endQuotedChar && !escaped)
                return _sql[_beginP.._p];

            if (escaped)
                escaped = false;
            else if (c == '\\')
                escaped = true;
        }

        _malformed = true;
        return _sql[_beginP.._p];
    }

    S readSpace() pure
    {
        while (_p < _sql.length)
        {
            const saveP = _p;
            if (charKind(readChar()) != CharKind.space)
            {
                _p = saveP;
                break;
            }
        }

        return _sql[_beginP.._p];
    }

private:
    S _sql, _currentParameterIndicator, _currentToken;
    size_t _p, _beginP;
    DbTokenKind _kind;
    bool _empty, _malformed;
}


// Any below codes are private
private:

version (unittest)
{
    void checkTokenizer(ref DbTokenizer!string tokenizer,
        bool empty, bool malformed, const(char)[] parameterIndicator, DbTokenKind kind, const(char)[] front,
        in int line = __LINE__)
    {
        import std.conv : to;

        assert(tokenizer.empty == empty, "empty #" ~ to!string(line));
        assert(tokenizer.malformed == malformed, "'"  ~ tokenizer.malformed ~ "' malformed #" ~ to!string(line));
        assert(tokenizer.parameterIndicator == parameterIndicator, "parameterIndicator #" ~ to!string(line));
        assert(tokenizer.kind == kind, "kind #" ~ to!string(line));
        assert(tokenizer.front == front, "'"  ~ tokenizer.front ~ "' front #" ~ to!string(line));
    }
}

unittest // DbTokenizer - empty
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("");
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Simple statement
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field) FROM test");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field)");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Single parameter
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field) FROM test Where varchar_field = @p0");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field)");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "varchar_field");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "@", DbTokenKind.parameterNamed, "p0");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Single parameter
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field) FROM test Where varchar_field = :p0");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field)");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "varchar_field");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, ":", DbTokenKind.parameterNamed, "p0");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Single parameter
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field) FROM test Where varchar_field = ?");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field)");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "varchar_field");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, "");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Multi parameters
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field) FROM test Where f1=@p1 and f2=:p2 and f3=?");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field)");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f1=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "@", DbTokenKind.parameterNamed, "p1");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "and");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f2=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, ":", DbTokenKind.parameterNamed, "p2");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "and");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f3=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, "");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Parameter with block comment
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string(" select count(int_field)  FROM test /* this is a comment with ' */  Where varchar_field = @_LongName$123 /**/ x=?");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field)");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, "  ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comment, "/* this is a comment with ' */");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, "  ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "varchar_field");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "@", DbTokenKind.parameterNamed, "_LongName$123");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comment, "/**/");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "x=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, "");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Parameter with line comment
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field), ' @ ' as ab, \" : \" ac, [ ad ] ad FROM test ? -- comment with @p123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field),");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.quotedSingle, "' @ '");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "as");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "ab,");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.quotedDouble, "\" : \"");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "ac,");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.quotedBracket, "[ ad ]");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "ad");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, "");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comment, "-- comment with @p123 ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Malformed multi parameters
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field) FROM test Where f1=@ and f2=: and f3=?");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field)");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f1=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "@", DbTokenKind.literal, "@");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "and");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f2=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, ":", DbTokenKind.literal, ":");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "and");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f3=");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, "");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Malform quoted
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field), ' @ -- comment with @p123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field),");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "", DbTokenKind.quotedSingle, "' @ -- comment with @p123 ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");

    tokenizer = DbTokenizer!string("select count(int_field), \" @ -- comment with @p123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field),");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "", DbTokenKind.quotedDouble, "\" @ -- comment with @p123 ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");

    tokenizer = DbTokenizer!string("select count(int_field), [ @ -- comment with @p123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field),");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "", DbTokenKind.quotedBracket, "[ @ -- comment with @p123 ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - Malform block comment
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string(" select count(int_field)  FROM test /* this is a comment with '  Where varchar_field = @_LongName$123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count(int_field)");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, "  ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "", DbTokenKind.comment, "/* this is a comment with '  Where varchar_field = @_LongName$123 ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer.parseParameter
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.parseParameter");

    static class StringList
    {
    nothrow @safe:

    public:
        StringList clear()
        {
            items.length = 0;
            return this;
        }

        void saveParameter(ref Appender!string result, string prmName, uint32 prmNo)
        {
            result.put('?');
            if (prmName.length)
                items ~= prmName;
        }

    public:
        string[] items;

        alias items this;
    }

    string s;
    auto slist = new StringList();

    slist.clear();
    assert(DbTokenizer!string.parseParameter("", &slist.saveParameter) == "");
    assert(slist.length == 0);

    slist.clear();
    s = DbTokenizer!string.parseParameter("select count(int_field) FROM test", &slist.saveParameter);
    assert(s == "select count(int_field) FROM test", s);
    assert(slist.length == 0);

    slist.clear();
    s = DbTokenizer!string.parseParameter("select count(int_field) FROM test Where varchar_field = @p0", &slist.saveParameter);
    assert(s == "select count(int_field) FROM test Where varchar_field = ?", s);
    assert(slist.length == 1);
    assert(slist[0] == "p0");

    slist.clear();
    s = DbTokenizer!string.parseParameter("select count(int_field) FROM test Where varchar_field = @p0 and int_field < :p1", &slist.saveParameter);
    assert(s == "select count(int_field) FROM test Where varchar_field = ? and int_field < ?", s);
    assert(slist.length == 2);
    assert(slist[0] == "p0");
    assert(slist[1] == "p1");

    slist.clear();
    s = DbTokenizer!string.parseParameter(" select count(int_field)  FROM test /* this is a comment with ' */  Where varchar_field = @_LongName$123 ", &slist.saveParameter);
    assert(s == " select count(int_field)  FROM test /* this is a comment with ' */  Where varchar_field = ? ", s);
    assert(slist.length == 1);
    assert(slist[0] == "_LongName$123");

    slist.clear();
    s = DbTokenizer!string.parseParameter("select count(int_field), ' @ ' as ab, \" : \" ac FROM test Where varchar_field = @p0 -- comment with @p123 ", &slist.saveParameter);
    assert(s == "select count(int_field), ' @ ' as ab, \" : \" ac FROM test Where varchar_field = ? -- comment with @p123 ", s);
    assert(slist.length == 1);
    assert(slist[0] == "p0");

    slist.clear();
    s = DbTokenizer!string.parseParameter("", &slist.saveParameter);
    assert(s == "", s);
    assert(slist.length == 0);
}

unittest // DbTokenizer - comment single line
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer.comment");

    auto tokenizer = DbTokenizer!string(" -- comment with \r\n ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comment, "-- comment with \r\n");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " ");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}

unittest // DbTokenizer - comment multi lines
{
    import pham.utl.test;
    traceUnitTest!("pham.db.database")("unittest pham.db.parser.DbTokenizer.comment");

    auto tokenizer = DbTokenizer!string(" \n/* comment with \r\n */ \n");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " \n");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comment, "/* comment with \r\n */");
    tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " \n");
    tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.space, "");
}
