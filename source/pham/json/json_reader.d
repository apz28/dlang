/*
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2025 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */
module pham.json.json_reader;

import std.conv : text, to;
import std.range : ElementType, empty, isSomeFiniteCharInputRange;
import std.traits : Unqual;

debug(debug_pham_utl_utl_json) import std.stdio : writeln;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_array_dictionary;
import pham.json.json_codec;
import pham.json.json_exception;
import pham.json.json_type;
import pham.json.json_value;

struct JSONToken(T)
{
    // Avoid UTF decoding when possible, as it is unnecessary when processing JSON.
    static if (is(T : const(char)[]))
    {
        alias Char = char;
        private enum useTSlice = true;
    }
    else
    {
        alias Char = Unqual!(ElementType!T);
        private enum useTSlice = false;
    }

nothrow @safe:

public:
    this(const(char)[] token, JSONTokenKind kind, size_t line, size_t column,
        string errorMessage = null)
    {
        static if (useTSlice)
            this._token = token;
        else
            this._token.put(token);
        this._kind = kind;
        this._line = line;
        this._column = column;
        this.errorMessage = errorMessage;
    }

    bool opEquals(scope const(typeof(this)) rhs) const @nogc pure
    {
        return this._kind == rhs._kind && this._token == rhs._token
            && this._line == rhs._line && this._column == rhs._column
            && this.errorMessage == rhs.errorMessage;
    }

    void clear()
    {
        errorMessage = null;
        _kind = JSONTokenKind.none;
        _line = _column = 0;
        clearToken();
    }

    pragma(inline, true)
    void clearToken() return
    {
        static if (useTSlice)
            _token = null;
        else
            _token.clear();
    }

    void setError(JSONTokenKind kind, size_t line, size_t column, string errorMessage)
    {
        _kind = kind;
        _line = line;
        _column = column;
        this.errorMessage = errorMessage;
    }

    pragma(inline, true)
    void setKind(JSONTokenKind kind, size_t line, size_t column)
    {
        _kind = kind;
        _line = line;
        _column = column;
    }

    string toString() const
    {
        import std.conv : textOf = text;
        import pham.utl.utl_enum_set : toName;

        const r = textOf(text, " [", toName(kind), ", ", line, ":", column, "]");
        return errorMessage.length == 0 ? r : (r ~ ": " ~ errorMessage);
    }

    @property size_t column() const
    {
        return _column;
    }

    pragma(inline, true)
    @property JSONTokenKind kind() const
    {
        return _kind;
    }

    @property size_t line() const
    {
        return _line;
    }

    @property const(char)[] text() const return
    {
        static if (useTSlice)
            return _token;
        else
            return _token.data;
    }

    string errorMessage;

private:
    static if (!useTSlice)
    {
        pragma(inline, true)
        void put(Char c)
        {
            _token.put(c);
        }

        static if (Char.sizeof != 1)
        {
            pragma(inline, true)
            void put(char c)
            {
                _token.put(c);
            }
        }
    }

    pragma(inline, true)
    void put(const(char)[] token)
    {
        static if (useTSlice)
            _token = token;
        else
            _token.put(token);
    }

private:
    static if (useTSlice)
        const(char)[] _token;
    else
        Appender!(char[]) _token;
    size_t _line, _column;
    JSONTokenKind _kind;
}

struct JSONTextTokenizer(T, JSONOptions options = defaultOptions)
{
    import std.typecons : Nullable, Yes;
    import std.uni : isSurrogateHi, isSurrogateLo;
    import std.utf : encode;
    import pham.utl.utl_utf8 : nextUTF16Char;

    static immutable string eofErrorMessage = "JSON - Unexpected end of data";

    // Avoid UTF decoding when possible, as it is unnecessary when processing JSON.
    static if (is(T : const(char)[]))
    {
        alias Char = char;
        private enum useTSlice = true;
    }
    else
    {
        alias Char = Unqual!(ElementType!T);
        private enum useTSlice = false;
    }

nothrow:

public:
    this(T json)
    {
        debug(debug_pham_utl_utl_json) static if (useTSlice) if (!__ctfe) debug writeln(__FUNCTION__, "(json=", json, ")");

        this.json = json;
        this._line = 1;
        popFront();
    }

    void popFront()
    {
        _token.clear();

        Char c;
        if (!getChar!true(c))
        {
            _token.setKind(JSONTokenKind.eof, 0, 0);
            return;
        }

        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(_nextCharP=", _nextCharP, ", _p=", _p, ", _line=", _line, ", _column=", _column, ", c=", c, ")");

        sLine = _line;
        sColumn = _column;

        switch (c)
        {
            case '{':
                _token.setKind(JSONTokenKind.beginObject, sLine, sColumn);
                return;

            case '}':
                _token.setKind(JSONTokenKind.endObject, sLine, sColumn);
                return;

            case '[':
                _token.setKind(JSONTokenKind.beginArray, sLine, sColumn);
                return;

            case ']':
                _token.setKind(JSONTokenKind.endArray, sLine, sColumn);
                return;

            case ':':
                _token.setKind(JSONTokenKind.colon, sLine, sColumn);
                return;

            case ',':
                _token.setKind(JSONTokenKind.comma, sLine, sColumn);
                return;

            // String
            static if (options & JSONOptions.json5)
            {
            case '"':
            case '\'':
                if (getString(_p, c))
                    _token.setKind(JSONTokenKind.string, sLine, sColumn);
                return;
            }
            else
            {
            case '"':
                if (getString(_p, c))
                    _token.setKind(JSONTokenKind.string, sLine, sColumn);
                return;
            }

            // Number
            case '0': .. case '9':
            case '+':
            case '-':
                if (const nt = getNumber(_p - 1, c))
                    _token.setKind(nt, sLine, sColumn);
                return;

            // Boolean false
            static if (options & JSONOptions.strictParsing)
            {
            case 'f':
            }
            else
            {
            case 'f':
            case 'F':
            }
                if (const fk = getFalse(_p - 1, c))
                {
                    if (fk == JSONTokenKind.false_)
                        _token.clearToken();
                    _token.setKind(fk, sLine, sColumn);
                }
                return;

            // Boolean true
            static if (options & JSONOptions.strictParsing)
            {
            case 't':
            }
            else
            {
            case 't':
            case 'T':
            }
                if (const tk = getTrue(_p - 1, c))
                {
                    if (tk == JSONTokenKind.true_)
                        _token.clearToken();
                    _token.setKind(tk, sLine, sColumn);
                }
                return;

            // null
            static if (options & JSONOptions.strictParsing)
            {
            case 'n':
            }
            else
            {
            case 'n':
            case 'N':
            }
                if (const nt = getNull(_p - 1, c))
                {
                    if (nt == JSONTokenKind.null_)
                        _token.clearToken();
                    _token.setKind(nt, sLine, sColumn);
                }
                return;

            static if (options & JSONOptions.json5)
            {
            case '/':
                const n = peekChar();
                if (n == '/' || n == '*')
                {
                    skipChar();
                    if (const ct = getComment(_p, n))
                        _token.setKind(ct, sLine, sColumn);
                    return;
                }
                else
                    goto default;
            }

            default:
                static if (options & JSONOptions.json5)
                {
                    if (isNameStart(c))
                    {
                        const nt = getName(_p - 1, c);
                        _token.setKind(nt, sLine, sColumn);
                        return;
                    }
                }

                static if (!useTSlice)
                    _token.put(c);
    
                setTokenError(text("JSON - Unexpected character '", JSONTextEncoder.encodeUtf8(c), "'"), _line, _column);
                return;
        }
    }

    pragma(inline, true)
    @property ref JSONToken!T front() return @safe
    {
        return _token;
    }

    pragma(inline, true)
    @property bool empty() const @safe
    {
        return _token.kind == JSONTokenKind.eof;
    }

private:
    // IdentifierName :: IdentifierStart || (IdentifierName && IdentifierPart)
    // IdentifierStart :: UnicodeLetter  || $  || _ || \UnicodeEscapeSequence
    // IdentifierPart :: IdentifierStart || UnicodeCombiningMark || UnicodeDigit || UnicodeConnectorPunctuation

    Char checkChar(bool SkipWhitespace = true)(const(Char) expectC1)
    {
        Char c;
        if (!getChar!SkipWhitespace(c))
            return setTokenEofError();

        static if (!useTSlice)
            _token.put(c);

        return isEqualChar(c, expectC1)
            ? c
            : setTokenError(text("JSON - Found '", c, "' when expecting '", JSONTextEncoder.encodeUtf8(expectC1), "'"), _line, _column);
    }

    Char checkChar(bool SkipWhitespace = true)(const(Char) expectC1, const(Char) expectC2)
    {
        Char c;
        if (!getChar!SkipWhitespace(c))
            return setTokenEofError();

        static if (!useTSlice)
            _token.put(c);

        return isEqualChar(c, expectC1, expectC2)
            ? c
            : setTokenError(text("JSON - Found '", c, "' when expecting '", JSONTextEncoder.encodeUtf8(expectC1), "'"), _line, _column);
    }

    pragma(inline, true)
    void clearNextChar()
    {
        _nextChar.nullify();
        static if (useTSlice)
            _nextCharP = 0;
        else
        {
            debug(debug_pham_utl_utl_json) _nextCharP = 0;
        }
    }

    bool getChar(bool SkipWhitespace = false)(ref Char c)
    {
        static if (SkipWhitespace)
            skipWhitespace();

        if (_nextChar.isNull)
        {
            if (jsonEmpty())
                return false;

            c = popChar();
            return true;
        }
        else
        {
            c = _nextChar.get;
            clearNextChar();
            return true;
        }
    }

    JSONTokenKind getComment(const(size_t) bp, Char c)
    {
        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(_nextCharP=", _nextCharP, ", _p=", _p, ", c=", c, ")");

        // Line comment?
        if (c == '\\')
        {
            while (getChar(c))
            {
                if (c == '\n')
                    break;

                static if (!useTSlice)
                    _token.put(c);
            }
            static if (useTSlice)
                _token.put(json[bp.._p]);
            debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln("\t", "comment=", _token.text);
            return JSONTokenKind.commentLine;
        }
        else
        {
            JSONTokenKind result = JSONTokenKind.none;
            while (getChar(c))
            {
                if (c == '*' && peekChar() == '/')
                {
                    result = JSONTokenKind.commentLines;
                    skipChar();
                    break;
                }

                static if (!useTSlice)
                    _token.put(c);
            }
            static if (useTSlice)
            {
                if (result == JSONTokenKind.commentLines)
                    _token.put(json[bp.._p - 2]);
            }
            debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln("\t", "comment=", _token.text);
            return result != JSONTokenKind.none ? result : setTokenEofError();
        }
    }

    // Returns false if failed or eos, true otherwise
    JSONTokenKind getDChar(ref dchar c)
    {
        wchar[2] pair;
        if (!getWChar(pair[0]))
            return JSONTokenKind.none;

        // Non-BMP characters are escaped as a pair of
        // UTF-16 surrogate characters (see RFC 4627).
        if (isSurrogateHi(pair[0]))
        {
            if (!testChar!false('\\'))
                return setTokenError("JSON - Expected escaped low surrogate after escaped high surrogate", _line, _column);
            if (!testChar!false('u', 'U'))
                return setTokenError("JSON - Expected escaped low surrogate after escaped high surrogate", _line, _column);
            if (!getWChar(pair[1]))
                return JSONTokenKind.none;

            ubyte count;
            if (!nextUTF16Char(pair[], 0, c, count) || count != 2)
                return setTokenError("JSON - Invalid escaped surrogate pair", _line, _column);
        }
        else if (isSurrogateLo(pair[0]))
            return setTokenError("JSON - Unexpected low surrogate", _line, _column);
        else
            c = pair[0];

        return JSONTokenKind.string;
    }

    JSONTokenKind getDigits(Char c)
    {
        if (!isDigit(c))
            return setTokenError(text("JSON - Digit expected: ", JSONTextEncoder.encodeUtf8(c)), _line, _column);

    Next:
        static if (!useTSlice)
            _token.put(c);

        if (isDigit(peekChar()))
        {
            getChar(c);
            goto Next;
        }

        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(_nextCharP=", _nextCharP, ", _p=", _p, ", c=", c, ")");

        return JSONTokenKind.integer;
    }

    JSONTokenKind getFalse(const(size_t) bp, Char c)
    {
        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(bp=", bp, ", c=", c, ")");

        static if (!useTSlice)
            _token.put(c);

        static if (options & JSONOptions.json5)
        {
            enum maxEqualLength = 4;
            static if (options & JSONOptions.strictParsing)
                static immutable Char[maxEqualLength] equalChars = "alse";
            else
                static immutable Char[2][maxEqualLength] equalChars = ["aA", "lL", "sS", "eE"];

            size_t length, equalLength;
            while (true)
            {
                c = peekChar();

                debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln("\t", "c=", c, ", length=", length,
                    ", equalLength=", equalLength, ", equalChars=", length < maxEqualLength ? equalChars[length] : "");

                if (!(isNameStart(c) || isDigit(c)))
                    break;

                skipChar();

                if (length < maxEqualLength && isEqualChar(c, equalChars[length]))
                    equalLength++;

                static if (!useTSlice)
                    _token.put(c);
                length++;
            }

            debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln("\t", "c=", c, ", length=", length, ", equalLength=", equalLength);

            static if (useTSlice)
                _token.put(json[bp.._nextCharP ? _nextCharP : _p]);
            return length == maxEqualLength && equalLength == maxEqualLength
                ? JSONTokenKind.false_
                : JSONTokenKind.name;
        }
        else
        {
            static if (options & JSONOptions.strictParsing)
                return checkChar!false('a') && checkChar!false('l') && checkChar!false('s') && checkChar!false('e')
                    ? JSONTokenKind.false_
                    : JSONTokenKind.none;
            else
                return checkChar!false('a', 'A') && checkChar!false('l', 'L') && checkChar!false('s', 'S') && checkChar!false('e', 'E')
                    ? JSONTokenKind.false_
                    : JSONTokenKind.none;
        }
    }

    JSONTokenKind getFloatSymbol(const(size_t) bp, Char c)
    {
        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(bp=", bp, ", c=", c, ")");

        static if (!useTSlice)
            _token.put(c);

        while (true)
        {
            c = peekChar();
            if (!isAlpha(c))
                break;

            skipChar();

            static if (!useTSlice)
                _token.put(c);
        }

        static if (useTSlice)
            _token.put(json[bp.._nextCharP ? _nextCharP : _p]);

        if (floatLiteralType(_token.text) == JSONFloatLiteralType.none)
            return setTokenError(text("JSON - Invalid float symbol: ", _token.text), sLine, sColumn);

        return JSONTokenKind.float_;
    }

    JSONTokenKind getHChar(ref char c)
    {
        uint c1, c2;
        if (!(getHexDigit(c1) && getHexDigit(c2)))
            return JSONTokenKind.none;

        c = cast(char)((c1 << 4) | c2);
        return JSONTokenKind.string;
    }

    JSONTokenKind getHexDigit(ref uint n)
    {
        Char c;

        if (!getChar(c))
            return setTokenEofError();

        if (!isHexDigit(c))
            return setTokenError(text("JSON - Expecting hex character: ", JSONTextEncoder.encodeUtf8(c)), _line, _column);

        n = isDigit(c) ? cast(ubyte)(c - '0') : cast(ubyte)((c | 0x20) - 'a' + 10);
        return JSONTokenKind.string;
    }

    JSONTokenKind getHexDigits(const(size_t) bp)
    {
        size_t length;
        while (true)
        {
            Char c = peekChar();

            if (!isHexDigit(c))
            {
                if (length == 0)
                    return jsonEmpty
                        ? setTokenEofError()
                        : setTokenError(text("JSON - Expecting hex character: ", JSONTextEncoder.encodeUtf8(c)), _line, _column);
                break;
            }

            length++;
            static if (!useTSlice)
                _token.put(c);
            skipChar();
        }

        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(bp=" , bp, ", length=", length, ", _nextCharP=", _nextCharP, ", _p=", _p, ")");

        static if (useTSlice)
            _token.put(json[bp.._nextCharP ? _nextCharP : _p]);

        return JSONTokenKind.integerHex;
    }

    JSONTokenKind getName(const(size_t) bp, Char c)
    {
        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(bp=", bp, ", c=", c, ", _nextCharP=", _nextCharP, ", _p=", _p, ")");

        static if (!useTSlice)
            _token.put(c);

        while (true)
        {
            c = peekChar();
            if (!(isNameStart(c) || isDigit(c)))
                break;

            skipChar();

            static if (!useTSlice)
                _token.put(c);
        }

        static if (useTSlice)
            _token.put(json[bp.._nextCharP ? _nextCharP : _p]);

        return floatLiteralType(_token.text) == JSONFloatLiteralType.none
            ? JSONTokenKind.name
            : JSONTokenKind.float_;
    }

    JSONTokenKind getNull(const(size_t) bp, Char c)
    {
        static if (!useTSlice)
            _token.put(c);

        static if (options & JSONOptions.json5)
        {
            enum maxEqualLength = 3;
            static if (options & JSONOptions.strictParsing)
                static immutable Char[maxEqualLength] equalChars = "ull";
            else
                static immutable Char[2][maxEqualLength] equalChars = ["uU", "lL", "lL"];

            size_t length, equalLength;
            while (true)
            {
                c = peekChar();
                if (!(isNameStart(c) || isDigit(c)))
                    break;

                skipChar();

                if (length < maxEqualLength && isEqualChar(c, equalChars[length]))
                    equalLength++;

                static if (!useTSlice)
                    _token.put(c);
                length++;
            }
            static if (useTSlice)
                _token.put(json[bp.._nextCharP ? _nextCharP : _p]);

            return length == maxEqualLength && equalLength == maxEqualLength
                ? JSONTokenKind.null_
                : (floatLiteralType(_token.text) == JSONFloatLiteralType.none
                    ? JSONTokenKind.name
                    : JSONTokenKind.float_);
        }
        else
        {
            static if (options & JSONOptions.strictParsing)
                return checkChar!false('u') && checkChar!false('l') && checkChar!false('l')
                    ? JSONTokenKind.null_
                    : JSONTokenKind.none;
            else
                return checkChar!false('u', 'U') && checkChar!false('l', 'L') && checkChar!false('l', 'L')
                    ? JSONTokenKind.null_
                    : JSONTokenKind.none;
        }
    }

    JSONTokenKind getNumber(size_t bp, Char c)
    {
        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(bp=", bp, ", c=", c, ", _nextCharP=", _nextCharP, ", _p=", _p, ")");

        JSONTokenKind result = JSONTokenKind.integer;

        if (c == '-')
        {
            static if (!useTSlice)
                _token.put('-');

            if (!getChar(c))
                return setTokenEofError();
        }
        else if (c == '+')
        {
            bp = _p; // Skip + sign
            if (!getChar(c))
                return setTokenEofError();
        }

        static if (options & JSONOptions.json5)
        {
            // Check for hex number?
            if (c == '0')
            {
                const n = peekChar();
                if (n == 'x' || n == 'X')
                {
                    static if (!useTSlice)
                    {
                        _token.put('0');
                        _token.put(n);
                    }
                    skipChar();
                    return getHexDigits(bp);
                }
            }
            // Check for special float symbol NaN or Infinity
            else if (c == 'N' || c == 'n' || c == 'I' || c == 'i')
                return getFloatSymbol(bp, c);
        }

        static if (options & JSONOptions.strictParsing)
        {
            if (c == '0')
            {
                const pc = peekChar();
                if (isDigit(pc))
                    return setTokenError(text("JSON - Additional digits not allowed after initial zero digit: ", JSONTextEncoder.encodeUtf8(pc)), _line, _column);
            }
        }

        if (!getDigits(c))
            return JSONTokenKind.none;

        if (testChar!false('.'))
        {
            result = JSONTokenKind.float_;
            static if (!useTSlice)
                _token.put('.');

            if (!getChar(c))
                return setTokenEofError();

            if (!getDigits(c))
                return JSONTokenKind.none;
        }

        if (testChar!false('e', 'E'))
        {
            result = JSONTokenKind.float_;
            static if (!useTSlice)
                _token.put('e');

            if (testChar!false('+'))
            {
                static if (!useTSlice)
                    _token.put('+');
            }
            else if (testChar!false('-'))
            {
                static if (!useTSlice)
                    _token.put('-');
            }

            if (!getChar(c))
                return setTokenEofError();

            if (!getDigits(c))
                return JSONTokenKind.none;
        }

        static if (useTSlice)
        {
            debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln("\t", "bp=", bp, ", _nextCharP=", _nextCharP, ", _p=", _p, ", c=", c);

            _token.put(json[bp..(_nextChar.isNull ? _p : _nextCharP)]);
        }

        return result;
    }

    JSONTokenKind getString(const(size_t) bp, const(Char) endingQuote)
    {
        debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln(__FUNCTION__, "(bp=", bp, ", _p=", _p, ")");

        static if (useTSlice)
        {
            Appender!string str;
            bool useStr;
            size_t ep;

            void copyTSlice() nothrow
            {
                debug(debug_pham_utl_utl_json) if (!__ctfe) writeln("\t", "bp=", bp, ", ep=", ep, ", c=", c);

                if (ep > bp)
                    str.put(json[bp..ep]);

                useStr = true;
            }
        }

        bool checkSeparator(const(dchar) c) nothrow
        {
            if (c == '\u2028' || c == '\u2029')
            {
                static if (useTSlice)
                {
                    if (!useStr)
                        copyTSlice();
                }
                return true;
            }
            else
                return false;
        }

        void putChar(char c) nothrow
        {
            static if (useTSlice)
            {
                if (!useStr)
                    copyTSlice();

                str.put(c);
            }
            else
            {
                _token.put(c);
            }
        }

    Next:
        static if (useTSlice)
            ep = _p;

        Char c;
        if (!getChar(c))
            return setTokenEofError();
        switch (c)
        {
            case '\\':
                if (!getChar(c))
                    return setTokenEofError();
                if (const es = JSONTextDecoder.escapeChar(c))
                    putChar(es);
                else if (c == 'u' || c == 'U')
                {
                    dchar val;
                    if (!getDChar(val))
                        return JSONTokenKind.none;

                    // Line separator | Paragraph separator
                    if (checkSeparator(val))
                        goto Next;

                    char[4] buf;
                    const len = encode!(Yes.useReplacementDchar)(buf, val);
                    foreach (e; buf[0..len])
                        putChar(e);
                }
                else
                {
                    static if (options & JSONOptions.json5)
                    {
                        if (c == 'x' || c == 'X')
                        {
                            char val;
                            if (!getHChar(val))
                                return JSONTokenKind.none;

                            // Line separator | Paragraph separator
                            if (checkSeparator(val))
                                goto Next;

                            putChar(val);
                            goto Next;
                        }
                    }

                    return setTokenError(text("JSON - Invalid escape sequence '\\", JSONTextEncoder.encodeUtf8(c), "'"), _line, _column);
                }

                goto Next;

            default:
                if (c == endingQuote)
                    break;

                // Line separator | Paragraph separator
                static if (Char.sizeof >= 2)
                {
                    if (checkSeparator(c))
                        goto Next;
                }

                // RFC 7159 states that control characters U+0000 through
                // U+001F must not appear unescaped in a JSON string.
                // Note: std.ascii.isControl can't be used for this test
                // because it considers ASCII DEL (0x7f) to be a control
                // character but RFC 7159 does not.
                // Accept unescaped ASCII NULs in non-strict mode.
                static if (options & JSONOptions.strictParsing)
                {
                    if (c < 0x20)
                        return setTokenError(text("JSON - Illegal control character: #", cast(int)c), _line, _column);
                }
                else
                {
                    if (c < 0x20 && c != 0)
                        return setTokenError(text("JSON - Illegal control character: #", cast(int)c), _line, _column);
                }

                static if (useTSlice)
                {
                    if (useStr)
                        str.put(c);
                }
                else
                {
                    _token.put(c);
                }
                goto Next;
        }

        static if (useTSlice)
        {
            debug(debug_pham_utl_utl_json) if (!__ctfe) debug writeln("\t", "useStr=", useStr, ", bp=", bp, ", _p=", _p);

            if (useStr)
                _token.put(str.data);
            else
                _token.put(json[bp.._p - 1]);
        }

        return JSONTokenKind.string;
    }

    JSONTokenKind getTrue(const(size_t) bp, Char c)
    {
        static if (!useTSlice)
            _token.put(c);

        static if (options & JSONOptions.json5)
        {
            enum maxEqualLength = 3;
            static if (options & JSONOptions.strictParsing)
                static immutable Char[maxEqualLength] equalChars = "rue";
            else
                static immutable Char[2][maxEqualLength] equalChars = ["rR", "uU", "eE"];

            size_t length, equalLength;
            while (true)
            {
                c = peekChar();
                if (!(isNameStart(c) || isDigit(c)))
                    break;

                skipChar();

                if (length < maxEqualLength && isEqualChar(c, equalChars[length]))
                    equalLength++;

                static if (!useTSlice)
                    _token.put(c);
                length++;
            }
            static if (useTSlice)
                _token.put(json[bp.._nextCharP ? _nextCharP : _p]);
            return length == maxEqualLength && equalLength == maxEqualLength
                ? JSONTokenKind.true_
                : JSONTokenKind.name;
        }
        else
        {
            static if (options & JSONOptions.strictParsing)
                return checkChar!false('r') && checkChar!false('u') && checkChar!false('e')
                    ? JSONTokenKind.true_
                    : JSONTokenKind.none;
            else
                return checkChar!false('r', 'R') && checkChar!false('u', 'U') && checkChar!false('e', 'E')
                    ? JSONTokenKind.true_
                    : JSONTokenKind.none;
        }
    }

    // Returns false if failed or eos, true otherwise
    JSONTokenKind getWChar(ref wchar c)
    {
        uint c1, c2, c3, c4;
        if (!(getHexDigit(c1) && getHexDigit(c2) && getHexDigit(c3) && getHexDigit(c4)))
            return JSONTokenKind.none;

        c = cast(wchar)((c1 << 12) | (c2 << 8) | (c3 << 4) | c4);
        return JSONTokenKind.string;
    }

    pragma(inline, true)
    static bool isAlpha(const(dchar) c) @nogc nothrow pure @safe
    {
        return ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z');
    }

    pragma(inline, true)
    static bool isDigit(const(dchar) c) @nogc nothrow pure @safe
    {
        return '0' <= c && c <= '9';
    }

    pragma(inline, true)
    static Char isEqualChar(const(Char) c, const(Char) c1) @nogc nothrow pure @safe
    {
        return c == c1 ? c : 0;
    }

    pragma(inline, true)
    static Char isEqualChar(const(Char) c, const(Char) c1, const(Char) c2) @nogc nothrow pure @safe
    {
        return c == c1 || c == c2 ? c : 0;
    }

    pragma(inline, true)
    static Char isEqualChar(const(Char) c, const(Char)[2] c2) @nogc nothrow pure @safe
    {
        return c == c2[0] || c == c2[1] ? c : 0;
    }

    pragma(inline, true)
    static bool isHexDigit(const(dchar) c) @nogc nothrow pure @safe
    {
        const hc = c | 0x20;
        return ('0' <= c && c <= '9') || ('a' <= hc && hc <= 'f');
    }

    pragma(inline, true)
    bool isNameStart(const(dchar) c)
    {
        return c == '_' || c == '$' || isAlpha(c);
    }

    pragma(inline, true)
    bool isWhite(const(dchar) c) @nogc nothrow pure @safe
    {
        static if (options & JSONOptions.strictParsing)
            // RFC 7159 has a stricter definition of whitespace than general ASCII.
            return c == ' ' || c == '\t' || c == '\n' || c == '\r';
        else
            // Accept ASCII NUL as whitespace in non-strict mode.
            return c == 0 || c == ' ' || (c >= 0x09 && c <= 0x0D);
    }

    pragma(inline, true)
    bool jsonEmpty()
    {
        static if (useTSlice)
            return _p >= json.length;
        else
            return json.empty;
    }

    Char peekChar()
    {
        if (_nextChar.isNull)
        {
            if (jsonEmpty())
                return '\0';

            setNextChar();
        }

        return _nextChar.get;
    }

    Nullable!Char peekCharNullable()
    {
        if (_nextChar.isNull && !jsonEmpty())
            setNextChar();

        return _nextChar;
    }

    Char popChar()
    {
        static if (useTSlice)
        {
            const Char c = json[_p++];
        }
        else
        {
            import std.range : front, popFront;
            
            debug(debug_pham_utl_utl_json) _p++;
            const Char c = json.front;
            json.popFront();
        }

        if (c == '\n')
        {
            _line++;
            _column = 0;
        }
        else if (c == '\r') // Check for crlf
        {
            _line++;
            _column = 0;
            if (!jsonEmpty())
            {
                static if (useTSlice)
                    const Char nc = json[_p];
                else
                    const Char nc = json.front;
                if (nc == '\n')
                {
                    static if (useTSlice)
                    {
                        _p++;
                    }
                    else
                    {
                        debug(debug_pham_utl_utl_json) _p++;
                        json.popFront();
                    }
                    return nc;
                }
            }
        }
        else
        {
            _column++;
        }

        return c;
    }

    pragma(inline, true)
    void setNextChar()
    {
        static if (useTSlice)
            _nextCharP = _p;
        else
        {
            debug(debug_pham_utl_utl_json) _nextCharP = _p;
        }
        _nextChar = popChar();
    }

    JSONTokenKind setTokenEofError()
    {
        _token.setError(JSONTokenKind.error, 0, 0, eofErrorMessage);
        return JSONTokenKind.none;
    }

    JSONTokenKind setTokenError(string errorMessage, size_t line, size_t column)
    {
        _token.setError(JSONTokenKind.error, line, column, errorMessage);
        return JSONTokenKind.none;
    }

    pragma(inline, true)
    void skipChar()
    {
        if (_nextChar.isNull)
            popChar();
        else
            clearNextChar();
    }

    void skipWhitespace()
    {
        while (true)
        {
            auto c = peekCharNullable();
            if (c.isNull || !isWhite(c.get))
                return;

            clearNextChar();
        }
    }

    Char testChar(bool SkipWhitespace = true)(const(Char) c1)
    {
        static if (SkipWhitespace)
            skipWhitespace();

        const c = peekChar();
        const r = isEqualChar(c, c1);
        if (r)
            skipChar();
        return r ? c : 0;
    }

    Char testChar(bool SkipWhitespace = true)(const(Char) c1, const(Char) c2)
    {
        static if (SkipWhitespace)
            skipWhitespace();

        const c = peekChar();
        const r = isEqualChar(c, c1, c2);
        if (r)
            skipChar();
        return r ? c : 0;
    }

public:
    T json;

private:
    JSONToken!T _token;
    size_t _p, _nextCharP;
    size_t _line, _column; // Current location of parsing text
    size_t sLine, sColumn; // Starting location of parsing text
    Nullable!Char _nextChar;
}

/**
 * Parses a serialized string and returns a tree of JSON values.
 * Throws:
 *  JSONException if string does not follow the JSON grammar or the depth exceeds the max depth,
 *      or a number in the input cannot be represented by a native D type.
 * Params:
 *  json = json-formatted string to parse
 *  options = enable decoding string representations of NaN/Inf as float values
 *  maxDepth = maximum depth of nesting allowed, 0 disables depth checking
 */
JSONValue parseJSON(T, JSONOptions options = defaultOptions)(T json, size_t maxDepth = 0)
if (isSomeFiniteCharInputRange!T)
{
    JSONValue root;

    auto tokenizer = JSONTextTokenizer!(T, options)(json);

    if (tokenizer.empty)
    {
        static if (options & JSONOptions.strictParsing)
            throw new JSONException("JSON - Empty body");

        return root;
    }

    noreturn error(string msg) @safe
    {
        if (tokenizer.front.kind == JSONTokenKind.error)
            throw new JSONException(tokenizer.front.errorMessage, tokenizer.front.line, tokenizer.front.column);
        else
            throw new JSONException(msg, tokenizer.front.line, tokenizer.front.column);
    }

    version(JSONCommentStore) string lastComment;
    int depth = -1;

    void parseComment() nothrow
    {
        version(JSONCommentStore)
        {
            if (lastComment.length == 0)
                lastComment = tokenizer.front.text.idup;
            else
            {
                lastComment ~= "\n";
                lastComment ~= tokenizer.front.text;
            }
        }
        tokenizer.popFront();

        while (isCommentTokenKind(tokenizer.front.kind))
        {
            version(JSONCommentStore)
            {
                lastComment ~= "\n";
                lastComment ~= tokenizer.front.text;
            }
            tokenizer.popFront();
        }
    }

    JSONTokenKind popFrontCheck() nothrow
    {
        if (isCommentTokenKind(tokenizer.front.kind))
            parseComment();
        return tokenizer.front.kind;
    }

    void parseValue(return ref JSONValue value)
    {
        depth++;
        if (maxDepth != 0 && depth > maxDepth)
            error("JSON - Nesting too deep");

    Next:
        final switch (tokenizer.front.kind)
        {
            case JSONTokenKind.null_:
                value.nullify();
                break;

            case JSONTokenKind.false_:
                value.nullify(JSONType.false_);
                break;

            case JSONTokenKind.true_:
                value.nullify(JSONType.true_);
                break;

            case JSONTokenKind.integer:
                const integerV = to!long(tokenizer.front.text);
                value.nullify(JSONType.integer)._store = JSONValue.Store(integer: integerV);
                break;

            case JSONTokenKind.integerHex:
                auto hexText = tokenizer.front.text;
                const isNeg = hexText[0] == '-';
                if (isNeg)
                    hexText = hexText[1..$];
                if (hexText.length >= 2 && (hexText[0..2] == "0x" || hexText[0..2] == "0X"))
                    hexText = hexText[2..$];
                const integerV = hexText.length > 8 ? to!long(hexText, 16) : to!int(hexText, 16);
                value.nullify(JSONType.integer)._store = JSONValue.Store(integer: isNeg ? -integerV : integerV);
                break;

            case JSONTokenKind.float_:
                static if (options & JSONOptions.json5)
                {
                    double floatingVS;
                    if (tryGetSpecialFloat(tokenizer.front.text, floatingVS))
                    {
                        // found a special float, its value was placed in value.store.floating
                        value.nullify(JSONType.float_)._store = JSONValue.Store(floating: floatingVS);
                        break;
                    }
                }
                const floatingV = to!double(tokenizer.front.text);
                value.nullify(JSONType.float_)._store = JSONValue.Store(floating: floatingV);
                break;

            case JSONTokenKind.string:
                static if (options & JSONOptions.specialFloatLiterals)
                {
                    // if special float parsing is enabled, check if string represents NaN/Inf
                    double floatingV;
                    if (tryGetSpecialFloat(tokenizer.front.text, floatingV))
                    {
                        // found a special float, its value was placed in value.store.floating
                        value.nullify(JSONType.float_)._store = JSONValue.Store(floating: floatingV);
                        break;
                    }
                }
                value.nullify(JSONType.string)._store = JSONValue.Store(str: tokenizer.front.text.idup);
                break;

            case JSONTokenKind.beginArray:
                JSONValue[] arrayV;
                tokenizer.popFront(); // Skip [
                while (true)
                {
                    auto kind = popFrontCheck();
                    if (kind == JSONTokenKind.endArray)
                        break;

                    // Check for next element separator
                    if (arrayV.length != 0)
                    {
                        if (kind != JSONTokenKind.comma)
                            error(text("Expected ',' or ']' but found '", tokenizer.front.text, "'"));
                        tokenizer.popFront();
                        kind = popFrontCheck();
                        static if ((options & JSONOptions.strictParsing) == 0)
                        {
                            if (kind == JSONTokenKind.endArray)
                                break;
                        }
                    }

                    // Get array element
                    JSONValue elementValue;
                    parseValue(elementValue);

                    arrayV ~= elementValue;
                }
                value.nullify(JSONType.array)._store = JSONValue.Store(array: arrayV);
                break;

            case JSONTokenKind.beginObject:
                Dictionary!(string, JSONValue) objectV;
                tokenizer.popFront(); // Skip {
                while (true)
                {
                    auto kind = popFrontCheck();
                    if (kind == JSONTokenKind.endObject)
                        break;

                    // Check for next member separator
                    if (objectV.length != 0)
                    {
                        if (kind != JSONTokenKind.comma)
                            error(text("Expected ',' or '}' but found '", tokenizer.front.text, "'"));
                        tokenizer.popFront();
                        kind = popFrontCheck();
                        static if ((options & JSONOptions.strictParsing) == 0)
                        {
                            if (kind == JSONTokenKind.endObject)
                                break;
                        }
                    }

                    if (!(kind == JSONTokenKind.string || kind == JSONTokenKind.name))
                        error(text("Expected field name but found '", tokenizer.front.text, "'"));

                    // Get member name
                    string memberKey = tokenizer.front.text.idup;
                    tokenizer.popFront();
                    kind = popFrontCheck();
                    if (kind != JSONTokenKind.colon)
                        error(text("Expected ':' but found '", tokenizer.front.text, "'"));
                    tokenizer.popFront();

                    // Get member value
                    JSONValue memberValue;
                    parseValue(memberValue);
                    version(JSONCommentStore)
                    {
                        memberValue.comment = lastComment;
                        lastComment = null;
                    }

                    objectV[memberKey] = memberValue;
                }
                value.nullify(JSONType.object)._store = JSONValue.Store(object: objectV);
                break;

            case JSONTokenKind.commentLine:
            case JSONTokenKind.commentLines:
                parseComment();
                goto Next;

            case JSONTokenKind.error:
                error(null);

            case JSONTokenKind.eof:
                error(tokenizer.eofErrorMessage);

            case JSONTokenKind.none:
            case JSONTokenKind.endArray:
            case JSONTokenKind.endObject:
            case JSONTokenKind.name:
            case JSONTokenKind.colon:
            case JSONTokenKind.comma:
                error(text("JSON - Unexpected text found '", tokenizer.front.text, "'"));
        }

        tokenizer.popFront();
        depth--;
    }

    try
    {
        parseValue(root);
    }
    catch (Exception e)
    {
        if (cast(JSONException)e !is null)
            throw e;
        else
            throw new JSONException(e.msg, e.file, e.line, e);
    }

    if (tokenizer.front.kind != JSONTokenKind.eof)
        error("JSON - Trailing non-whitespace characters");

    return root;
}

JSONValue parseJSON(JSONOptions options, T)(T json, size_t maxDepth = 0)
if (isSomeFiniteCharInputRange!T)
{
    return parseJSON!(T, options)(json, maxDepth);
}

version(unittest)
{
    package static string diffLoc(scope const(char)[] left, scope const(char)[] right) nothrow pure @safe
    {
        import std.conv : text;

        int line = 1, column;
        foreach (i; 0..left.length)
        {
            if (left[i] == '\n')
            {
                line++;
                column = 0;
            }
            column++;

            if (i >= right.length)
                break;

            if (left[i] != right[i])
                return text(left[i], " vs ", right[i], " ", line, ":", column);
        }

        return left.length != right.length
            ? text(left.length, " vs ", right.length)
            : null;
    }

    package static void checkTokens(Tokenizer, S)(ref Tokenizer tokens, JSONToken!S[] expectTokens, uint line = __LINE__) nothrow @safe
    {
        uint count;
        while (!tokens.empty)
        {
            assert(count < expectTokens.length, () { debug return text("More tokens then expected: ", count + 1, " vs ", expectTokens.length, " @", line); }());
            assert(tokens.front == expectTokens[count], () { debug return text("\n", tokens.front, "\n", expectTokens[count], "\n@line# ", line, '\n', diffLoc(tokens.front.toString, expectTokens[count].toString)); }());

            count++;
            if (tokens.front.kind == JSONTokenKind.error)
                break;
            tokens.popFront();
        }
        assert(count == expectTokens.length, () { debug return text("Less tokens then expected: ", count, " vs ", expectTokens.length, " @", line); }());
    }
}


private:

nothrow @safe unittest // JSONTextTokenizer - Ok
{
    alias Tokenizer = JSONTextTokenizer!(string, optionsOf([JSONOptions.specialFloatLiterals]));
    Tokenizer tokens;

    tokens = Tokenizer("false");
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.false_, 1, 1)]);

    tokens = Tokenizer("true");
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.true_, 1, 1)]);

    tokens = Tokenizer("null");
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.null_, 1, 1)]);

    tokens = Tokenizer("1234");
    checkTokens(tokens, [JSONToken!string("1234", JSONTokenKind.integer, 1, 1)]);

    tokens = Tokenizer("1234.25");
    checkTokens(tokens, [JSONToken!string("1234.25", JSONTokenKind.float_, 1, 1)]);

    tokens = Tokenizer(`"ab1234"`);
    checkTokens(tokens, [JSONToken!string("ab1234", JSONTokenKind.string, 1, 1)]);

    tokens = Tokenizer(`"D \" \\ \/ \b \f \n \r \t D"`);
    checkTokens(tokens, [JSONToken!string("D \" \\ / \b \f \n \r \t D", JSONTokenKind.string, 1, 1)]);

    tokens = Tokenizer(`false, true, null, -1234, +1234.25, "ab1234"`);
    checkTokens(tokens, [
        JSONToken!string(null, JSONTokenKind.false_, 1, 1),
        JSONToken!string(null, JSONTokenKind.comma, 1, 6),
        JSONToken!string(null, JSONTokenKind.true_, 1, 8),
        JSONToken!string(null, JSONTokenKind.comma, 1, 12),
        JSONToken!string(null, JSONTokenKind.null_, 1, 14),
        JSONToken!string(null, JSONTokenKind.comma, 1, 18),
        JSONToken!string("-1234", JSONTokenKind.integer, 1, 20),
        JSONToken!string(null, JSONTokenKind.comma, 1, 25),
        JSONToken!string("1234.25", JSONTokenKind.float_, 1, 27),
        JSONToken!string(null, JSONTokenKind.comma, 1, 35),
        JSONToken!string("ab1234", JSONTokenKind.string, 1, 37)]);

    tokens = Tokenizer(`{"a":[1,2,3], "b":null, "c":false, "d":true,
"E":-1234, "f":1.7E+3, "g":" +1234 "}`);
    checkTokens(tokens, [
        JSONToken!string(null, JSONTokenKind.beginObject, 1, 1),
        JSONToken!string("a", JSONTokenKind.string, 1, 2),
        JSONToken!string(null, JSONTokenKind.colon, 1, 5),
        JSONToken!string(null, JSONTokenKind.beginArray, 1, 6),
        JSONToken!string("1", JSONTokenKind.integer, 1, 7),
        JSONToken!string(null, JSONTokenKind.comma, 1, 8),
        JSONToken!string("2", JSONTokenKind.integer, 1, 9),
        JSONToken!string(null, JSONTokenKind.comma, 1, 10),
        JSONToken!string("3", JSONTokenKind.integer, 1, 11),
        JSONToken!string(null, JSONTokenKind.endArray, 1, 12),
        JSONToken!string(null, JSONTokenKind.comma, 1, 13),
        JSONToken!string("b", JSONTokenKind.string, 1, 15),
        JSONToken!string(null, JSONTokenKind.colon, 1, 18),
        JSONToken!string(null, JSONTokenKind.null_, 1, 19),
        JSONToken!string(null, JSONTokenKind.comma, 1, 23),
        JSONToken!string("c", JSONTokenKind.string, 1, 25),
        JSONToken!string(null, JSONTokenKind.colon, 1, 28),
        JSONToken!string(null, JSONTokenKind.false_, 1, 29),
        JSONToken!string(null, JSONTokenKind.comma, 1, 34),
        JSONToken!string("d", JSONTokenKind.string, 1, 36),
        JSONToken!string(null, JSONTokenKind.colon, 1, 39),
        JSONToken!string(null, JSONTokenKind.true_, 1, 40),
        JSONToken!string(null, JSONTokenKind.comma, 1, 44),
        JSONToken!string("E", JSONTokenKind.string, 2, 1),
        JSONToken!string(null, JSONTokenKind.colon, 2, 4),
        JSONToken!string("-1234", JSONTokenKind.integer, 2, 5),
        JSONToken!string(null, JSONTokenKind.comma, 2, 10),
        JSONToken!string("f", JSONTokenKind.string, 2, 12),
        JSONToken!string(null, JSONTokenKind.colon, 2, 15),
        JSONToken!string("1.7E+3", JSONTokenKind.float_, 2, 16),
        JSONToken!string(null, JSONTokenKind.comma, 2, 22),
        JSONToken!string("g", JSONTokenKind.string, 2, 24),
        JSONToken!string(null, JSONTokenKind.colon, 2, 27),
        JSONToken!string(" +1234 ", JSONTokenKind.string, 2, 28),
        JSONToken!string(null, JSONTokenKind.endObject, 2, 37),
        ]);
}

nothrow @safe unittest // JSONTextTokenizer(json5) - Ok
{
    alias Tokenizer = JSONTextTokenizer!(string, optionsOf([JSONOptions.specialFloatLiterals, JSONOptions.json5]));
    Tokenizer tokens;

    tokens = Tokenizer("0x1234");
    checkTokens(tokens, [JSONToken!string("0x1234", JSONTokenKind.integerHex, 1, 1)]);

    tokens = Tokenizer("falseN");
    checkTokens(tokens, [JSONToken!string("falseN", JSONTokenKind.name, 1, 1)]);

    tokens = Tokenizer("trueN");
    checkTokens(tokens, [JSONToken!string("trueN", JSONTokenKind.name, 1, 1)]);

    tokens = Tokenizer("nullN");
    checkTokens(tokens, [JSONToken!string("nullN", JSONTokenKind.name, 1, 1)]);

    tokens = Tokenizer(`ab1234`);
    checkTokens(tokens, [JSONToken!string("ab1234", JSONTokenKind.name, 1, 1)]);

    tokens = Tokenizer(`NaN`);
    checkTokens(tokens, [JSONToken!string("NaN", JSONTokenKind.float_, 1, 1)]);

    tokens = Tokenizer(`-NaN`);
    checkTokens(tokens, [JSONToken!string("-NaN", JSONTokenKind.float_, 1, 1)]);

    tokens = Tokenizer(`Infinity`);
    checkTokens(tokens, [JSONToken!string("Infinity", JSONTokenKind.float_, 1, 1)]);

    tokens = Tokenizer(`-Infinity`);
    checkTokens(tokens, [JSONToken!string("-Infinity", JSONTokenKind.float_, 1, 1)]);

    tokens = Tokenizer(`{"a":[1,2,3], "b":null, "c":false, "d":true,
"E":-1234, "f":1.7E+3, "g":" +1234 ", xyzName:0x1234, }`);
    checkTokens(tokens, [
        JSONToken!string(null, JSONTokenKind.beginObject, 1, 1),
        JSONToken!string("a", JSONTokenKind.string, 1, 2),
        JSONToken!string(null, JSONTokenKind.colon, 1, 5),
        JSONToken!string(null, JSONTokenKind.beginArray, 1, 6),
        JSONToken!string("1", JSONTokenKind.integer, 1, 7),
        JSONToken!string(null, JSONTokenKind.comma, 1, 8),
        JSONToken!string("2", JSONTokenKind.integer, 1, 9),
        JSONToken!string(null, JSONTokenKind.comma, 1, 10),
        JSONToken!string("3", JSONTokenKind.integer, 1, 11),
        JSONToken!string(null, JSONTokenKind.endArray, 1, 12),
        JSONToken!string(null, JSONTokenKind.comma, 1, 13),
        JSONToken!string("b", JSONTokenKind.string, 1, 15),
        JSONToken!string(null, JSONTokenKind.colon, 1, 18),
        JSONToken!string(null, JSONTokenKind.null_, 1, 19),
        JSONToken!string(null, JSONTokenKind.comma, 1, 23),
        JSONToken!string("c", JSONTokenKind.string, 1, 25),
        JSONToken!string(null, JSONTokenKind.colon, 1, 28),
        JSONToken!string(null, JSONTokenKind.false_, 1, 29),
        JSONToken!string(null, JSONTokenKind.comma, 1, 34),
        JSONToken!string("d", JSONTokenKind.string, 1, 36),
        JSONToken!string(null, JSONTokenKind.colon, 1, 39),
        JSONToken!string(null, JSONTokenKind.true_, 1, 40),
        JSONToken!string(null, JSONTokenKind.comma, 1, 44),
        JSONToken!string("E", JSONTokenKind.string, 2, 1),
        JSONToken!string(null, JSONTokenKind.colon, 2, 4),
        JSONToken!string("-1234", JSONTokenKind.integer, 2, 5),
        JSONToken!string(null, JSONTokenKind.comma, 2, 10),
        JSONToken!string("f", JSONTokenKind.string, 2, 12),
        JSONToken!string(null, JSONTokenKind.colon, 2, 15),
        JSONToken!string("1.7E+3", JSONTokenKind.float_, 2, 16),
        JSONToken!string(null, JSONTokenKind.comma, 2, 22),
        JSONToken!string("g", JSONTokenKind.string, 2, 24),
        JSONToken!string(null, JSONTokenKind.colon, 2, 27),
        JSONToken!string(" +1234 ", JSONTokenKind.string, 2, 28),
        JSONToken!string(null, JSONTokenKind.comma, 2, 37),
        JSONToken!string("xyzName", JSONTokenKind.name, 2, 39),
        JSONToken!string(null, JSONTokenKind.colon, 2, 46),
        JSONToken!string("0x1234", JSONTokenKind.integerHex, 2, 47),
        JSONToken!string(null, JSONTokenKind.comma, 2, 53),
        JSONToken!string(null, JSONTokenKind.endObject, 2, 55),
        ]);
}

nothrow @safe unittest // JSONTextTokenizer - Failed
{
    alias Tokenizer = JSONTextTokenizer!(string, optionsOf([JSONOptions.specialFloatLiterals]));
    Tokenizer tokens;

    tokens = Tokenizer(`"`); // unterminated string
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 0, 0, tokens.eofErrorMessage)]);

    tokens = Tokenizer(`"\`); // unterminated string escape sequence
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 0, 0, tokens.eofErrorMessage)]);

    tokens = Tokenizer(`"test\"`); // unterminated string
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 0, 0, tokens.eofErrorMessage)]);

    tokens = Tokenizer(`"test'`); // unterminated string
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 0, 0, tokens.eofErrorMessage)]);

    tokens = Tokenizer("\"test\n\""); // illegal control character
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 2, 0, "JSON - Illegal control character: #10")]);

    tokens = Tokenizer(`"\x"`); // invalid escape sequence
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 1, 3, "JSON - Invalid escape sequence '\\x'")]);

    tokens = Tokenizer(`"\u123`); // unterminated unicode escape sequence
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 0, 0, tokens.eofErrorMessage)]);

    tokens = Tokenizer(`"\u123G"`); // invalid unicode escape sequence
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 1, 7, "JSON - Expecting hex character: G")]);

    tokens = Tokenizer(`"\uD800"`); // missing surrogate
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 1, 8, "JSON - Expected escaped low surrogate after escaped high surrogate")]);

    tokens = Tokenizer(`"\uD800\u"`); // too short second surrogate
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 1, 10, "JSON - Expecting hex character: \"")]);

    tokens = Tokenizer(`"\uD800\u1234"`); // invalid surrogate pair
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 1, 13, "JSON - Invalid escaped surrogate pair")]);
}

nothrow @safe unittest // JSONTextTokenizer(json5) - Failed
{
    alias Tokenizer = JSONTextTokenizer!(string, optionsOf([JSONOptions.specialFloatLiterals, JSONOptions.json5]));
    Tokenizer tokens;

    tokens = Tokenizer(`"0x'`); // unterminated hex integer
    checkTokens(tokens, [JSONToken!string(null, JSONTokenKind.error, 0, 0, tokens.eofErrorMessage)]);
}

unittest
{
    alias Tokenizer = JSONTextTokenizer!(dstring, optionsOf([JSONOptions.specialFloatLiterals, JSONOptions.json5]));
    Tokenizer tokens;
    
    tokens = Tokenizer(`" "`d);
    checkTokens(tokens, [JSONToken!dstring("", JSONTokenKind.string, 1, 1)]);
    
    tokens = Tokenizer(`[" "]`d);
    checkTokens(tokens, [
        JSONToken!dstring(null, JSONTokenKind.beginArray, 1, 1),
        JSONToken!dstring("", JSONTokenKind.string, 1, 2),
        JSONToken!dstring(null, JSONTokenKind.endArray, 1, 5),
        ]);
}
