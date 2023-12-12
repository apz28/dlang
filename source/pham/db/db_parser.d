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

module pham.db.db_parser;

import std.array : Appender;
import std.uni : isAlphaNum, isSpace;

version (unittest) import pham.utl.utl_test;
import pham.utl.utl_enum_set : toEnum;
import pham.utl.utl_result : addLine;
import pham.utl.utl_utf8 : nextUTF8Char;
public import pham.utl.utl_result : ResultIf;
import pham.utl.utl_text : NamedValue;
import pham.db.db_message;
public import pham.db.db_message : DbErrorCode;
import pham.db.db_type : DbHost, DbScheme, DbURL, isDbScheme, uint32;

nothrow @safe:

enum DbTokenKind : ubyte
{
    space,
    commentSingle, // --xyz... or ##xyz...
    commentMulti, // /*xyz...*/
    spaceLine, // Space with line break
    literal,
    quotedSingle, // 'xyz...' or `xyz...`
    quotedDouble, // "xyz..."
    parameterNamed,  // :xyz... or @xyz...
    parameterUnnamed, // ?
    comma, // ,
    bracketBegin, // [ -> [xyz...]
    bracketEnd, // ] -> [xyz...]
    parenthesisBegin, // ( -> (xyz...)
    parenthesisEnd, // ) -> (xyz...)
    eos, // end of stream/string
}

enum DbTokenSkipLevel : ubyte
{
    none,
    space,
    comment,
    spaceLine,
}

// S should be either 'const(char)[]' or 'string'
struct DbTokenizer(S, DbTokenSkipLevel skipLevel = DbTokenSkipLevel.none)
{
nothrow @safe:

public:
    dchar replacementChar = dchar.max;

public:
    this(S sql) pure
    {
        this._sql = sql;
        this.reset();
    }

    ptrdiff_t isCurrentKind(scope const(DbTokenKind)[] kinds) @nogc pure
    {
        foreach (i; 0..kinds.length)
        {
            if (kinds[i] == _currentKind)
                return i;
        }
        return -1;
    }

    void popFront() pure
    {
        popFrontImpl();
        static if (skipLevel != DbTokenSkipLevel.none)
        {
            enum skipTokenLevel = skipLevel == DbTokenSkipLevel.space
                ? DbTokenKind.space
                : (skipLevel == DbTokenSkipLevel.comment
                    ? DbTokenKind.commentMulti
                    : (skipLevel == DbTokenSkipLevel.spaceLine
                        ? DbTokenKind.spaceLine
                        : assert(0, "Missing implementing of DbTokenSkipLevel element")));
            while (_currentKind <= skipTokenLevel)
                popFrontImpl();
        }
    }

    void reset() pure
    {
        _p = _beginP = 0;
        _lastKinds = null;
        popFront();
    }

    static S removeQuoteIf(S s) pure
    {
        if (s.length <= 1)
            return s;

        return s[0] == s[$ - 1] && (s[0] == '"' || s[0] == '`' || s[0] == '\'')
            ? s[1..$ - 1]
            : s;
    }

    pragma(inline, true)
    @property bool empty() const @nogc pure
    {
        return _currentKind == DbTokenKind.eos;
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
        return _currentKind;
    }

    @property const(DbTokenKind)[] lastKinds() const @nogc pure
    {
        return _lastKinds;
    }

    @property size_t offset() const @nogc pure
    {
        return _p;
    }

    @property S parameterIndicator() const @nogc pure
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
        commentSingle,
        commentMulti,
        spaceLine,
        literal,
        quotedSingle,
        quotedDouble,
        parameterNamed,
        parameterUnnamed,
        comma,
        bracketBegin,
        bracketEnd,
        parenthesisBegin,
        parenthesisEnd,
    }

    enum SpaceKind : ubyte
    {
        none,
        space,
        spaceLine,
    }

    static CharKind charKind(const(dchar) c) @nogc pure
    {
        switch (c)
        {
            case '@':
            case ':':
                return CharKind.parameterNamed;
            case '?':
                return CharKind.parameterUnnamed;
            case '`':
            case '\'':
                return CharKind.quotedSingle;
            case '"':
                return CharKind.quotedDouble;
            case ',':
                return CharKind.comma;
            case '[':
                return CharKind.bracketBegin;
            case ']':
                return CharKind.bracketEnd;
            case '(':
                return CharKind.parenthesisBegin;
            case ')':
                return CharKind.parenthesisEnd;
            case '-':
            case '#':
                return CharKind.commentSingle;
            case '/':
                return CharKind.commentMulti;
            default:
                const p = isSpaceChar(c);
                return p == SpaceKind.spaceLine
                    ? CharKind.spaceLine
                    : (p == SpaceKind.space ? CharKind.space : CharKind.literal);
        }
    }

    pragma(inline, true)
    static bool isNameChar(const(dchar) c) @nogc pure
    {
        //import pham.utl.utl_test; dgWriteln("c=", c, ", isAlphaNum(c)=", isAlphaNum(c));

        return c == '_' || c == '$' || isAlphaNum(c);
    }

    pragma(inline, true)
    static SpaceKind isSpaceChar(const(dchar) c) @nogc pure
    {
        return c == '\n' || c == '\r'
            ? SpaceKind.spaceLine
            : (c == '\t' || isSpace(c) ? SpaceKind.space : SpaceKind.none);
    }

    void popFrontImpl() pure
    {
        _currentParameterIndicator = null;
        _malformed = false;
        _beginP = _p;

        if (_p >= _sql.length)
        {
            _currentParameterIndicator = _currentToken = null;
            _currentKind = DbTokenKind.eos;
            _malformed = _lastKinds.length != 0;
            return;
        }

        void closeToken(DbTokenKind openKind)
        {
            if (_lastKinds.length == 0 || _lastKinds[$ - 1] != openKind)
                _malformed = true;
            else
                _lastKinds = _lastKinds[0..$ - 1];
        }

        void literalToken()
        {
            _currentToken = _sql[_beginP.._p];
            _currentKind = DbTokenKind.literal;
        }

        const c = readChar();
        final switch (charKind(c))
        {
            case CharKind.space:
                _currentKind = DbTokenKind.space;
                _currentToken = readSpace(_currentKind);
                return;

            case CharKind.spaceLine:
                _currentKind = DbTokenKind.spaceLine;
                _currentToken = readSpace(_currentKind);
                return;

            case CharKind.quotedSingle:
                _currentToken = readQuoted(c);
                _currentKind = DbTokenKind.quotedSingle;
                return;

            case CharKind.quotedDouble:
                _currentToken = readQuoted(c);
                _currentKind = DbTokenKind.quotedDouble;
                return;

            case CharKind.parameterUnnamed:
                _currentParameterIndicator = _sql[_beginP.._p];
                _currentToken = null;
                _currentKind = DbTokenKind.parameterUnnamed;
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
                        _currentKind = DbTokenKind.parameterNamed;
                        return;
                    }
                    else
                        _p = parameter2P;
                }
                _malformed = true;
                _currentToken = _currentParameterIndicator;
                _currentKind = DbTokenKind.literal;
                return;

            case CharKind.comma:
                _currentToken = ",";
                _currentKind = DbTokenKind.comma;
                return;

            case CharKind.bracketBegin:
                _currentToken = "[";
                _currentKind = DbTokenKind.bracketBegin;
                _lastKinds ~= DbTokenKind.bracketBegin;
                return;

            case CharKind.bracketEnd:
                _currentToken = "]";
                _currentKind = DbTokenKind.bracketEnd;
                return closeToken(DbTokenKind.bracketBegin);

            case CharKind.parenthesisBegin:
                _currentToken = "(";
                _currentKind = DbTokenKind.parenthesisBegin;
                _lastKinds ~= DbTokenKind.parenthesisBegin;
                return;

            case CharKind.parenthesisEnd:
                _currentToken = ")";
                _currentKind = DbTokenKind.parenthesisEnd;
                return closeToken(DbTokenKind.parenthesisBegin);

            case CharKind.commentSingle:
                if (_p < _sql.length)
                {
                    const commentSingleP = _p;
                    if (readChar() == c)
                    {
                        _currentToken = readCommentSingle();
                        _currentKind = DbTokenKind.commentSingle;
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
                        _currentKind = DbTokenKind.commentMulti;
                        return;
                    }
                    else
                        _p = commentMultiP;
                }
                return literalToken();

            case CharKind.literal:
                _currentToken = readLiteral();
                _currentKind = DbTokenKind.literal;
                return literalToken();
        }
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
                break;
            else if (c == 0x0D)
            {
                // Skip return line feed?
                if (_p < _sql.length)
                {
                    const saveP = _p;
                    if (readChar() != 0x0A)
                        _p = saveP;
                }
                break;
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
        //import pham.utl.utl_test; dgWriteln("_beginP=", _beginP, ", _sql=", _sql[_beginP.._p]);

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

    S readSpace(ref DbTokenKind tk) pure
    {
        while (_p < _sql.length)
        {
            const saveP = _p;
            const ck = charKind(readChar());
            if (ck == CharKind.space)
                continue;
            else if (ck == CharKind.spaceLine)
            {
                tk = DbTokenKind.spaceLine;
                continue;
            }
            else
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
    DbTokenKind[] _lastKinds;
    DbTokenKind _currentKind;
    bool _malformed;
}

struct DbTokenErrorMessage
{
    import pham.utl.utl_result : ResultIf;

nothrow @safe:

    static string conversion(string sqlKind, string fromValue, string toType) pure
    {
        scope (failure) assert(0, "Assume nothrow failed");
        
        return DbMessage.eMalformSQLStatementConversion.fmtMessage(sqlKind, fromValue, toType);
    }

    static string eos(string sqlKind) pure
    {
        scope (failure) assert(0, "Assume nothrow failed");
        
        return DbMessage.eMalformSQLStatementEos.fmtMessage(sqlKind);
    }

    static ResultIf!T eosResult(T)(string sqlKind)
    {
        return ResultIf!T.error(DbErrorCode.parse, eos(sqlKind));
    }

    static string keyword(string sqlKind, string expected, string found) pure
    {
        scope (failure) assert(0, "Assume nothrow failed");
        
        return DbMessage.eMalformSQLStatementKeyword.fmtMessage(sqlKind, expected, found);
    }

    static ResultIf!T keywordResult(T)(string sqlKind, string expected, string found)
    {
        return ResultIf!T.error(DbErrorCode.parse, keyword(sqlKind, expected, found));
    }

    static string other(string sqlKind, string expected, string found) pure
    {
        scope (failure) assert(0, "Assume nothrow failed");
        
        return DbMessage.eMalformSQLStatementOther.fmtMessage(sqlKind, expected, found);
    }

    static ResultIf!T otherResult(T)(string sqlKind, string expected, string found)
    {
        return ResultIf!T.error(DbErrorCode.parse, other(sqlKind, expected, found));
    }

    static string reKeyword(string sqlKind, string keyword) pure
    {
        scope (failure) assert(0, "Assume nothrow failed");
        
        return DbMessage.eMalformSQLStatementReKeyword.fmtMessage(sqlKind, keyword);
    }

    static ResultIf!T reKeywordResult(T)(string sqlKind, string keyword)
    {
        return ResultIf!T.error(DbErrorCode.parse, reKeyword(sqlKind, keyword));
    }
}

S parseParameter(S)(S sql, void delegate(ref Appender!S result, S parameterName, uint32 parameterNumber) nothrow @safe parameterCallBack)
in
{
    assert(parameterCallBack !is null);
}
do
{
    version (TraceFunction) traceFunction("sql.length=", sql.length);

    if (sql.length == 0)
        return sql;

    size_t prevP, beginP;
    uint32 parameterNumber; // Based 1 value
    auto result = Appender!S();
    auto tokenizer = DbTokenizer!S(sql);
    while (!tokenizer.empty)
    {
        //import pham.utl.utl_test; dgWriteln("tokenizer.kind=", tokenizer.kind, ", tokenizer.front=", tokenizer.front);

        final switch (tokenizer.kind)
        {
            case DbTokenKind.parameterNamed:
            case DbTokenKind.parameterUnnamed:
                // Leading text before parameter?
                if (beginP < prevP)
                {
                    //import pham.utl.utl_test; dgWriteln("sql[beginP..prevP]=", sql[beginP..prevP]);

                    result.put(sql[beginP..prevP]);
                }

                // save info for next round
                beginP = tokenizer.offset;

                parameterCallBack(result, tokenizer.front, ++parameterNumber);
                break;

            case DbTokenKind.space:
            case DbTokenKind.commentSingle:
            case DbTokenKind.commentMulti:
            case DbTokenKind.spaceLine:
            case DbTokenKind.literal:
            case DbTokenKind.quotedSingle:
            case DbTokenKind.quotedDouble:
            case DbTokenKind.comma:
            case DbTokenKind.bracketBegin:
            case DbTokenKind.bracketEnd:
            case DbTokenKind.parenthesisBegin:
            case DbTokenKind.parenthesisEnd:
            case DbTokenKind.eos:
                break;
        }

        prevP = tokenizer.offset;
        tokenizer.popFront();
    }

    //import pham.utl.utl_test; dgWriteln("tokenizer.kind=", tokenizer.kind, ", tokenizer.front=", tokenizer.front, ", parameterNumber=", parameterNumber);

    if (parameterNumber == 0)
        return sql;
    else
    {
        // Remaining text?
        if (beginP < sql.length)
        {
            //import pham.utl.utl_test; dgWriteln("sql[beginP..$]=", sql[beginP..$]);

            result.put(sql[beginP..$]);
        }

        return result.data;
    }
}

/**
 * DbScheme://[username:password@]host1[:port1][,host2[:port2],...[,hostN[:portN]]][/[<database>][?<options>]]
 * <database>
 *   string
 * <options>
 *   <name>=<value>[,<name>=<value>]
 * <name>
 *   string
 * <value>
 *   [quoted]string[quoted]
 *
 * Example
 *   firebird://SYSDBA:masterkey@localhost:3050/c:\data\firebird.fdb?compress=1,encrypt=1
 */
ResultIf!(DbURL!S) parseDbURL(S)(S dbURL)
{
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;
    import pham.utl.utl_text : NamedValue, parseFormEncodedValues, simpleIndexOf, simpleIndexOfAny, simpleSplitter;

    auto currentURL = dbURL;
    size_t currentOffset = 0;
    DbURL!S result;
    string errorMessage;

    ResultIf!(DbURL!S) returnResult() nothrow @safe
    {
        return errorMessage.length == 0
            ? ResultIf!(DbURL!S).ok(result)
            : ResultIf!(DbURL!S).error(result, DbErrorCode.parse, errorMessage);
    }

    // Required
    bool parseScheme() nothrow @safe
    {
        bool schemeError(string message) nothrow @safe
        {
            addLine(errorMessage, message);
            addLine(errorMessage, "Scheme specification is expected to be of the form '<SCHEME_NAME>://'");
            return false;
        }

        const i = currentURL.simpleIndexOf("://");
        if (i <= 0)
            return schemeError("Missing scheme separator <://>");

        const scheme = currentURL[0..i];
        currentURL = currentURL[i + 3..$];
        currentOffset += i + 3;

        if (!isDbScheme(scheme, result.scheme))
            return schemeError("Invalid scheme: " ~ scheme.idup ~ ".");

        return true;
    }

    if (!parseScheme())
        return returnResult();

    // Optional; if defined, userName must not be empty
    bool parseIdentity() nothrow @safe
    {
        bool identityError(string message) nothrow @safe
        {
            addLine(errorMessage, message);
            addLine(errorMessage, "Identity specification is expected to be of the form '://<USER_NAME:PASSWORD>@'");
            return false;
        }

        const i = currentURL.simpleIndexOf('@');
        if (i < 0)
            return true;

        const identity = currentURL[0..i];
        currentURL = currentURL[i + 1..$];
        currentOffset += i + 1;

        const iColon = identity.simpleIndexOf(':');
        if (iColon < 0)
            result.userName = identity;
        else
        {
            result.userName = identity[0..iColon];
            result.userPassword = identity[iColon + 1..$];
        }

        if (result.userName.length != 0)
            return true;

        return identityError("Missing user-name.");
    }

    if (!parseIdentity())
        return returnResult();

    bool parseHost() nothrow @safe
    {
        bool hostError(string message) nothrow @safe
        {
            addLine(errorMessage, message);
            addLine(errorMessage, "Host specifications are expected to be of the form '@<HOST:PORT>,<HOST:PORT>,.../'");
            return false;
        }

        S hosts;
        const i = currentURL.simpleIndexOf('/');
        if (i >= 0)
        {
            hosts = currentURL[0..i];
            currentURL = currentURL[i + 1..$];
            currentOffset += i + 1;
        }
        else
        {
            hosts = currentURL;
            currentOffset += currentURL.length;
            currentURL = null;
        }

        foreach (host; hosts.simpleSplitter(','))
		{
            auto hostPort = host.simpleSplitter(':');
			S h = hostPort.front;
            if (h.length == 0)
                return hostError("Missing host-name.");
            ushort p = 0;
			hostPort.popFront();
			if (!hostPort.empty)
            {
                auto ps = hostPort.front;
                hostPort.popFront();
				if (parseIntegral!(S, ushort)(ps, p) != NumericParsedKind.ok)
                    return hostError("Invalid port: " ~ ps.idup ~ ".");
			}
            if (!hostPort.empty)
                return hostError("Invalid host/port: " ~ host.idup ~ ".");
			result.hosts ~= DbHost!S(h, p);
		}

        if (result.hosts.length != 0)
            return true;

        return hostError("Missing host.");
    }

    if (!parseHost())
        return returnResult();

    bool parseDatabase() nothrow @safe
    {
        bool databaseError(string message) nothrow @safe
        {
            addLine(errorMessage, message);
            addLine(errorMessage, "Database specification is expected to be of the form '/<DATABASE_NAME>?'");
            return false;
        }

        const i = currentURL.simpleIndexOf('?');
        if (i >= 0)
        {
            result.database = currentURL[0..i];
            currentURL = currentURL[i + 1..$];
            currentOffset += i + 1;
        }
        else
        {
            result.database = currentURL;
            currentOffset += currentURL.length;
            currentURL = null;
        }

        if (result.database.length != 0)
            return true;

        return databaseError("Missing database-name.");
    }

    if (!parseDatabase())
        return returnResult();

    bool parsedOption(size_t index, ResultIf!S name, ResultIf!S value) nothrow @safe
    {
        if (name && value)
        {
            result.options ~= NamedValue!S(name, value);
            return true;
        }
        else
        {
            if (!name)
                addLine(errorMessage, name.errorMessage ~ ".");
            if (!value)
                addLine(errorMessage, value.errorMessage ~ ".");
            addLine(errorMessage, "Option specifications are expected to be of the form '?<NAME=VALUE>&<NAME=VALUE>&...'");
            return false;
        }
    }

    if (currentURL.length != 0)
        parseFormEncodedValues(currentURL, &parsedOption);

    return returnResult();
}

// Any below codes are private
private:

version (unittest)
{
    const(char)[] quoteBool(bool token, bool expected, const(char)[] name, int line)
    {
        import std.conv : to;

        return "'" ~ token.to!string() ~ " vs " ~ expected.to!string() ~ "' " ~ name ~ " from line# " ~ line.to!string();
    }

    const(char)[] quoteKind(DbTokenKind token, DbTokenKind expected, const(char)[] name, int line)
    {
        import std.conv : to;
        import pham.utl.utl_enum_set : toName;

        return "'" ~ token.toName() ~ " vs " ~ expected.toName() ~ "' " ~ name ~ " from line# " ~ line.to!string();
    }

    const(char)[] quoteStr(const(char)[] token, const(char)[] expected, const(char)[] name, int line)
    {
        import std.conv : to;

        return "'" ~ token ~ " vs " ~ expected ~ "' " ~ name ~ " from line# " ~ line.to!string();
    }

    void checkTokenizer(T)(ref T tokenizer,
        bool empty, bool malformed, const(char)[] parameterIndicator, DbTokenKind kind, const(char)[] front,
        in uint line = __LINE__)
    {
        import std.conv : to;
        import pham.utl.utl_enum_set : toName;

        assert(tokenizer.empty == empty, "empty from line# " ~ line.to!string());
        assert(tokenizer.malformed == malformed, quoteBool(tokenizer.malformed, malformed, "malformed", line));
        assert(tokenizer.parameterIndicator == parameterIndicator, quoteStr(tokenizer.parameterIndicator, parameterIndicator, "parameterIndicator", line));
        assert(tokenizer.kind == kind, quoteKind(tokenizer.kind, kind, "kind", line));
        assert(tokenizer.front == front, quoteStr(tokenizer.front, front, "front", line));
    }
}

unittest // DbTokenizer - empty
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("");
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Simple statement
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field), [bracket] FROM test");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisBegin, "("); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisEnd, ")"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketBegin, "["); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "bracket"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketEnd, "]"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Single parameter
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field), [bracket] FROM test Where varchar_field = @p0");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisBegin, "("); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisEnd, ")"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketBegin, "["); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "bracket"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketEnd, "]"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "varchar_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "@", DbTokenKind.parameterNamed, "p0"); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Single parameter
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field), [bracket] FROM test Where varchar_field = :p0");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisBegin, "("); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisEnd, ")"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketBegin, "["); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "bracket"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketEnd, "]"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "varchar_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, ":", DbTokenKind.parameterNamed, "p0"); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Single parameter
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field), [bracket] FROM test Where varchar_field = ?");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisBegin, "("); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisEnd, ")"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketBegin, "["); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "bracket"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketEnd, "]"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "varchar_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, ""); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Multi parameters
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field), [bracket] FROM test Where f1=@p1 and f2=:p2 and f3=?");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisBegin, "("); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisEnd, ")"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketBegin, "["); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "bracket"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketEnd, "]"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f1="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "@", DbTokenKind.parameterNamed, "p1"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "and"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f2="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, ":", DbTokenKind.parameterNamed, "p2"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "and"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f3="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, ""); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Parameter with block comment
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string(" select count(int_field, int_field2), [bracket, bracket2] FROM test /* this is a comment with ' */  Where varchar_field = @_LongName$123 /**/ x=?");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisBegin, "("); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field2"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisEnd, ")"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketBegin, "["); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "bracket"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "bracket2"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketEnd, "]"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.commentMulti, "/* this is a comment with ' */"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, "  "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "varchar_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "@", DbTokenKind.parameterNamed, "_LongName$123"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.commentMulti, "/**/"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "x="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, ""); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Parameter with line comment
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select count(int_field), ' @ ' as ab, \" : \" ac, [ ad ] ad FROM test ? -- comment with @p123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "count"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisBegin, "("); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.parenthesisEnd, ")"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.quotedSingle, "' @ '"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "as"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "ab"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.quotedDouble, "\" : \""); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "ac"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketBegin, "["); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "ad"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketEnd, "]"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "ad"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, ""); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.commentSingle, "-- comment with @p123 "); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Malformed multi parameters
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select int_field FROM test Where f1=@ and f2=: and f3=?");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "Where"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f1="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "@", DbTokenKind.literal, "@"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "and"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f2="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, ":", DbTokenKind.literal, ":"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "and"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "f3="); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "?", DbTokenKind.parameterUnnamed, ""); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Malform quoted
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("select int_field ' @ -- comment with @p123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "", DbTokenKind.quotedSingle, "' @ -- comment with @p123 "); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");

    tokenizer = DbTokenizer!string("select , \" @ -- comment with @p123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "", DbTokenKind.quotedDouble, "\" @ -- comment with @p123 "); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");

    tokenizer = DbTokenizer!string("select int_field, [ -- comment with @p123 \n");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "select"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "int_field"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.comma, ","); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.bracketBegin, "["); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.commentSingle, "-- comment with @p123 \n"); tokenizer.popFront();
    checkTokenizer(tokenizer, true, true, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - Malform block comment
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer");

    auto tokenizer = DbTokenizer!string("FROM test /* this is a comment with '  Where varchar_field = @_LongName$123 ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "FROM"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.literal, "test"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, true, "", DbTokenKind.commentMulti, "/* this is a comment with '  Where varchar_field = @_LongName$123 "); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - comment single line
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer.comment");

    auto tokenizer = DbTokenizer!string(" -- comment with \r\n ");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.commentSingle, "-- comment with \r\n"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.space, " "); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - comment multi lines
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer.comment");

    auto tokenizer = DbTokenizer!string(" \n/* comment with \r\n */ \n");
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.spaceLine, " \n"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.commentMulti, "/* comment with \r\n */"); tokenizer.popFront();
    checkTokenizer(tokenizer, false, false, "", DbTokenKind.spaceLine, " \n"); tokenizer.popFront();
    checkTokenizer(tokenizer, true, false, "", DbTokenKind.eos, "");
}

unittest // DbTokenizer - SkipLevel
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.DbTokenizer.SkipLevel");

    auto tokenizerSpace = DbTokenizer!(string, DbTokenSkipLevel.space)("FROM test /* this is a comment */ @_LongName$123 \n ");
    checkTokenizer(tokenizerSpace, false, false, "", DbTokenKind.literal, "FROM"); tokenizerSpace.popFront();
    checkTokenizer(tokenizerSpace, false, false, "", DbTokenKind.literal, "test"); tokenizerSpace.popFront();
    checkTokenizer(tokenizerSpace, false, false, "", DbTokenKind.commentMulti, "/* this is a comment */");  tokenizerSpace.popFront();
    checkTokenizer(tokenizerSpace, false, false, "@", DbTokenKind.parameterNamed, "_LongName$123"); tokenizerSpace.popFront();
    checkTokenizer(tokenizerSpace, false, false, "", DbTokenKind.spaceLine, " \n "); tokenizerSpace.popFront();
    checkTokenizer(tokenizerSpace, true, false, "", DbTokenKind.eos, "");

    auto tokenizerComment = DbTokenizer!(string, DbTokenSkipLevel.comment)("FROM test /* comment1 */ /* comment2 */ @_LongName$123 \n ");
    checkTokenizer(tokenizerComment, false, false, "", DbTokenKind.literal, "FROM"); tokenizerComment.popFront();
    checkTokenizer(tokenizerComment, false, false, "", DbTokenKind.literal, "test"); tokenizerComment.popFront();
    checkTokenizer(tokenizerComment, false, false, "@", DbTokenKind.parameterNamed, "_LongName$123"); tokenizerComment.popFront();
    checkTokenizer(tokenizerComment, false, false, "", DbTokenKind.spaceLine, " \n "); tokenizerComment.popFront();
    checkTokenizer(tokenizerComment, true, false, "", DbTokenKind.eos, "");

    auto tokenizerSpaceLine = DbTokenizer!(string, DbTokenSkipLevel.spaceLine)("FROM test /* comment1 */ /* comment2 */ \n \n @_LongName$123 \n ");
    checkTokenizer(tokenizerSpaceLine, false, false, "", DbTokenKind.literal, "FROM"); tokenizerSpaceLine.popFront();
    checkTokenizer(tokenizerSpaceLine, false, false, "", DbTokenKind.literal, "test"); tokenizerSpaceLine.popFront();
    checkTokenizer(tokenizerSpaceLine, false, false, "@", DbTokenKind.parameterNamed, "_LongName$123"); tokenizerSpaceLine.popFront();
    checkTokenizer(tokenizerSpaceLine, true, false, "", DbTokenKind.eos, "");
}

unittest // parseParameter
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.parseParameter");

    static struct StringList
    {
    nothrow @safe:

    public:
        ref StringList clear()
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
    StringList slist;

    slist.clear();
    assert(parseParameter("", &slist.saveParameter) == "");
    assert(slist.length == 0);

    slist.clear();
    s = parseParameter("select count(int_field) FROM test", &slist.saveParameter);
    assert(s == "select count(int_field) FROM test", s);
    assert(slist.length == 0);

    slist.clear();
    s = parseParameter("select count(int_field) FROM test Where varchar_field = @p0", &slist.saveParameter);
    assert(s == "select count(int_field) FROM test Where varchar_field = ?", s);
    assert(slist.length == 1);
    assert(slist[0] == "p0");

    slist.clear();
    s = parseParameter("select count(int_field) FROM test Where varchar_field = @p0 and int_field < :p1", &slist.saveParameter);
    assert(s == "select count(int_field) FROM test Where varchar_field = ? and int_field < ?", s);
    assert(slist.length == 2);
    assert(slist[0] == "p0");
    assert(slist[1] == "p1");

    slist.clear();
    s = parseParameter(" select count(int_field)  FROM test /* this is a comment with ' */  Where varchar_field = @_LongName$123 ", &slist.saveParameter);
    assert(s == " select count(int_field)  FROM test /* this is a comment with ' */  Where varchar_field = ? ", s);
    assert(slist.length == 1);
    assert(slist[0] == "_LongName$123");

    slist.clear();
    s = parseParameter("select count(int_field), ' @ ' as ab, \" : \" ac FROM test Where varchar_field = @p0 -- comment with @p123 ", &slist.saveParameter);
    assert(s == "select count(int_field), ' @ ' as ab, \" : \" ac FROM test Where varchar_field = ? -- comment with @p123 ", s);
    assert(slist.length == 1);
    assert(slist[0] == "p0");

    slist.clear();
    s = parseParameter("", &slist.saveParameter);
    assert(s == "", s);
    assert(slist.length == 0);
}

unittest // parseDbURL
{
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.parser.parseDbURL");

    auto cfg = parseDbURL("firebird://SYSDBA:masterkey@localhost/baz");
    assert(cfg, cfg.getErrorString());
    assert(cfg.scheme == DbScheme.fb);
	assert(cfg.userName == "SYSDBA", cfg.userName);
	assert(cfg.userPassword == "masterkey", cfg.userPassword);
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost", cfg.hosts[0].name);
	assert(cfg.hosts[0].port == 0);
	assert(cfg.database == "baz", cfg.database);
    assert(cfg.options.length == 0);

    cfg = parseDbURL("firebird://SYSDBA:@localhost/baz");
    assert(cfg, cfg.getErrorString());
    assert(cfg.scheme == DbScheme.fb);
	assert(cfg.userName == "SYSDBA", cfg.userName);
	assert(cfg.userPassword.length == 0);
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost", cfg.hosts[0].name);
	assert(cfg.hosts[0].port == 0);
	assert(cfg.database == "baz", cfg.database);
    assert(cfg.options.length == 0);

	cfg = parseDbURL("postgresql://ROOT:flinstone@host1.example.com,host2.other.example.com:27108,host3:27019"
				~ "/postgresql?journal=true;connectTimeout=1500;socketTimeout=1000");
    assert(cfg, cfg.getErrorString());
    assert(cfg.scheme == DbScheme.pg);
	assert(cfg.userName == "ROOT", cfg.userName);
	assert(cfg.userPassword == "flinstone", cfg.userPassword);
	assert(cfg.hosts.length == 3);
	assert(cfg.hosts[0].name == "host1.example.com", cfg.hosts[0].name);
	assert(cfg.hosts[0].port == 0);
	assert(cfg.hosts[1].name == "host2.other.example.com", cfg.hosts[1].name);
	assert(cfg.hosts[1].port == 27108);
	assert(cfg.hosts[2].name == "host3", cfg.hosts[2].name);
	assert(cfg.hosts[2].port == 27019);
	assert(cfg.database == "postgresql", cfg.database);
    assert(cfg.options.length == 3);
	assert(cfg.option("journal") == "true");
	assert(cfg.option("connectTimeout") == "1500");
	assert(cfg.option("socketTimeout") == "1000");

	cfg = parseDbURL("mysql://me:sl$ash/w0+rd@localhost/mydb");
    assert(cfg, cfg.getErrorString());
    assert(cfg.scheme == DbScheme.my);
	assert(cfg.userName == "me", cfg.userName);
	assert(cfg.userPassword == "sl$ash/w0+rd", cfg.userPassword);
	assert(cfg.hosts.length == 1);
	assert(cfg.hosts[0].name == "localhost", cfg.hosts[0].name);
	assert(cfg.hosts[0].port == 0);
	assert(cfg.database == "mydb", cfg.database);
    assert(cfg.options.length == 0);

    // Invalid URLs
    cfg = parseDbURL("localhost:27018"); assert(!cfg, cfg.getErrorString());
    cfg = parseDbURL("http://blah"); assert(!cfg, cfg.getErrorString());
    cfg = parseDbURL("firebird://@localhost"); assert(!cfg, cfg.getErrorString());
    cfg = parseDbURL("mysql://:thepass@localhost"); assert(!cfg, cfg.getErrorString());
    cfg = parseDbURL("postgresql://:badport/"); assert(!cfg, cfg.getErrorString());
}
