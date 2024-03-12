/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2022 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_text;

public import pham.utl.utl_result : ResultIf;

nothrow @safe:

struct NamedValue(S)
{
    S name;
    S value;
}

ptrdiff_t indexOf(S)(scope const(NamedValue!S)[] values, scope const(S) name) pure
{
    foreach (i, ref v; values)
    {
        if (v.name == name)
            return i;
    }
    return -1;
}

S valueOf(S)(NamedValue!S[] values, scope const(S) name, S notFound = S.init) pure
{
    foreach (ref v; values)
    {
        if (v.name == name)
            return v.value;
    }
    return notFound;
}

ResultIf!S decodeFormValue(S)(S encodedFormValue, const(char) invalidReplacementChar) pure
{
    import std.array : Appender;
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseHexDigits;

    if (encodedFormValue.simpleIndexOfAny("%+") < 0)
        return ResultIf!S.ok(encodedFormValue);

    S firstErrorText;
    ptrdiff_t firstErrorIndex = -1;

    auto result = Appender!S();
    result.reserve(encodedFormValue.length);

    size_t i = 0;
    while (i < encodedFormValue.length)
    {
        const c = encodedFormValue[i++];
		switch (c)
        {
			case '%':
                if (encodedFormValue.length < (i + 2))
                {
                    if (firstErrorIndex == -1)
                    {
                        firstErrorIndex = i - 1;
                        firstErrorText = encodedFormValue[(i - 1)..$];
                    }
                    if (invalidReplacementChar != '\0')
                        result.put(invalidReplacementChar);
                }
                else
                {
                    ubyte h;
                    if (parseHexDigits!(S, ubyte)(encodedFormValue[i..(i + 2)], h) == NumericParsedKind.ok)
                        result.put(cast(char)h);
                    else
                    {
                        if (firstErrorIndex == -1)
                        {
                            firstErrorIndex = i - 1;
                            firstErrorText = encodedFormValue[(i - 1)..(i + 2)];
                        }
                        if (invalidReplacementChar != '\0')
                            result.put(invalidReplacementChar);
                    }
                }
				i += 2;
				break;
            // Relax decoding
			case '+':
                result.put(' ');
                break;
			default:
				result.put(c);
				break;
		}
	}
    return firstErrorIndex == -1
        ? ResultIf!S.ok(result.data)
        : ResultIf!S.error(result.data, cast(int)firstErrorIndex, "Invalid form-encoded character: " ~ firstErrorText.idup);
}

/**
 * Returns true if `c` is in the range 0..0x7F
 * Params:
 *   c = the character to test
 */
pragma(inline, true)
bool isSimpleChar(const(char) c) @nogc pure
{
    return c <= 0x7F;
}

/**
 * Returns true if all characters `chars` are in the range 0..0x7F
 * Params:
 *   chars = the list of characters to test
 */
bool isAllSimpleChar(scope const(char)[] chars) @nogc pure
{
    foreach (i; 0..chars.length)
    {
        if (!isSimpleChar(chars[i]))
            return false;
    }
    return true;
}

void parseFormEncodedValues(S)(S formEncodedValues, bool delegate(size_t index, ResultIf!S name, ResultIf!S value) nothrow @safe valueCallBack)
{
    enum invalidReplacementChar = '?';
    size_t counter;
    ResultIf!S name, value;
    foreach (formEncodedValue; formEncodedValues.simpleSplitter("&;"))
    {
        const i = formEncodedValue.simpleIndexOf('=');
        if (i >= 0)
        {
            name = decodeFormValue(formEncodedValue[0..i], invalidReplacementChar);
            value = decodeFormValue(formEncodedValue[(i + 1)..$], invalidReplacementChar);
        }
        else
        {
            name = decodeFormValue(formEncodedValue, invalidReplacementChar);
            value = ResultIf!S.ok(null);
        }
        if (!valueCallBack(counter++, name, value))
            break;
    }
}

/**
 * Finds the first occurence of character `c` in string `str` and returns its index.
 * No auto decode
 * Params:
 *   str = string
 *   c = a character to look for
 * Returns:
 *   index of `c` in `str` if found
 *   -1 if not found
 */
ptrdiff_t simpleIndexOf(C)(scope const(C)[] str, const(C) c) @nogc pure
{
	foreach (i; 0..str.length)
    {
		if (str[i] == c)
			return i;
    }
	return -1;
}

/**
 * Finds the first occurence of sub-string `subStr` in string `str` and returns its index.
 * No auto decode
 * Params:
 *   str = string
 *   subStr = a sub-string to look for
 * Returns:
 *   index of `subStr` in `str` if found
 *   -1 if not found
 */
ptrdiff_t simpleIndexOf(C)(scope const(C)[] str, scope const(C)[] subStr) @nogc pure
{
    if (str.length < subStr.length || subStr.length == 0)
        return -1;

    const c0 = subStr[0];
	foreach (i; 0..(str.length - subStr.length + 1))
    {
		if (str[i] == c0)
        {
            bool m = true;
            foreach (j; 1..subStr.length)
            {
                if (str[i + j] != subStr[j])
                {
                    m = false;
                    break;
                }
            }
            if (m)
                return i;
        }
    }
	return -1;
}

/**
 * Finds the first occurence of any character `chars` in `str` and returns its index.
 * No auto decode
 * Params:
 *   str = string
 *   chars = list of characters to look for
 * Returns:
 *   index of any `chars` in `str`
 *   -1 if not found
 */
ptrdiff_t simpleIndexOfAny(C)(scope const(C)[] str, scope const(C)[] chars) @nogc pure
{
	foreach (i; 0..str.length)
    {
		if (simpleIndexOf(chars, str[i]) >= 0)
			return i;
    }
	return -1;
}

auto simpleSplitter(S, Separator)(S str, Separator separator)
{
    import std.traits : isSomeChar;

    struct Result
    {
    nothrow @safe:

    public:
        this(S input, Separator separator)
        {
            this._input = input;
            this._separator = separator;
            this._frontLength = input.length == 0 ? atEnd : unComputed;
        }

        void popFront()
        in
        {
            assert(!empty, "Attempting to fetch the front of an empty simpleSplitter.");
        }
        do
        {
            if (_frontLength == unComputed)
                computeFrontLength();

            // no more input and need to fetch => done
            if (_frontLength == _input.length)
                _frontLength = atEnd;
            else
            {
                _input = _input[(_frontLength + 1)..$];
                _frontLength = unComputed;
            }
        }

        @property bool empty() const
        {
            return _frontLength == atEnd;
        }

        @property S front()
        in
        {
            assert(!empty, "Attempting to fetch the front of an empty simpleSplitter.");
        }
        do
        {
            if (_frontLength == unComputed)
                computeFrontLength();

            return _input[0.._frontLength];
        }

    private:
        void computeFrontLength()
        {
            foreach (i; 0.._input.length)
            {
                if (isSeparator(i))
                {
                    _frontLength = i;
                    return;
                }
            }
            _frontLength = _input.length;
        }

        pragma(inline, true)
        bool isSeparator(const(size_t) i) const
        {
            static if (isSomeChar!Separator)
                return _separator == _input[i];
            else
                return simpleIndexOf(_separator, _input[i]) >= 0;
        }

    private:
        enum size_t unComputed = size_t.max - 1, atEnd = size_t.max;

        S _input;
        Separator _separator;
        size_t _frontLength;
    }

    return Result(str, separator);
}


private:

nothrow @safe unittest // isSimpleChar
{
    assert(isSimpleChar('a'));
    assert(!isSimpleChar(0x82));
}

nothrow @safe unittest // isAllSimpleChar
{
    assert(isAllSimpleChar("az"));
    assert(!isAllSimpleChar("áz"));
}

nothrow @safe unittest // simpleIndexOf
{
    string s = "Hello World";
    assert(simpleIndexOf(s, 'W') == 6);
    assert(simpleIndexOf(s, 'z') == -1);
    assert(simpleIndexOf(s, 'w') == -1);
}

nothrow @safe unittest // simpleIndexOf
{
    string s = "Hello World";
    assert(simpleIndexOf(s, "Wo") == 6);
    assert(simpleIndexOf(s, null) == -1);
    assert(simpleIndexOf(s, s ~ "?") == -1);
    assert(simpleIndexOf(s, "Hello?") == -1);
    assert(simpleIndexOf(s, "zo") == -1);
    assert(simpleIndexOf(s, "wo") == -1);
}

nothrow @safe unittest // simpleIndexOfAny
{
    string s = "Hello World";
    assert(simpleIndexOfAny(s, "Wr") == 6);
    assert(simpleIndexOfAny(s, "or") == 4);
    assert(simpleIndexOfAny(s, "zx") == -1);
}

nothrow @safe unittest  // simpleSplitter
{
    import std.algorithm.comparison : equal;

    string[] empty;

    assert("".simpleSplitter('|').equal(empty));
    assert("|".simpleSplitter('|').equal(["", ""]));
    assert("||".simpleSplitter('|').equal(["", "", ""]));
    assert("|a|bc|def|".simpleSplitter('|').equal(["", "a", "bc", "def", ""]));
    assert("a|bc|def".simpleSplitter('|').equal(["a", "bc", "def"]));
}

nothrow @safe unittest // decodeFormValue
{
    assert(decodeFormValue("Hello World", '\0') == "Hello World");
    assert(decodeFormValue("%0D%0a", '\0') == "\r\n");
	assert(decodeFormValue("%c2%aE", '\0') == "®");
	assert(decodeFormValue("This+is%20a+test", '\0') == "This is a test");
    assert(decodeFormValue("This~is%20a-test%21%0D%0AHello%2C%20W%C3%B6rld..%20", '\0') == "This~is a-test!\r\nHello, Wörld.. ");
}

nothrow @safe unittest // parseFormEncodedValues
{
    string[string] values;

    bool parsedValue(size_t index, ResultIf!string name, ResultIf!string value) nothrow @safe
    {
        values[name] = value;
        return true;
    }

    values = null;
    parseFormEncodedValues("a=b;c;dee=asd&e=fgh&f=j%20l", &parsedValue);
    assert("a" in values && values["a"] == "b");
	assert("c" in values && values["c"] == "");
	assert("dee" in values && values["dee"] == "asd");
	assert("e" in values && values["e"] == "fgh");
	assert("f" in values && values["f"] == "j l");
}
