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

import std.format.spec : FormatSpec;
import std.traits : Unqual, isFloatingPoint, isIntegral, isSomeChar, isSomeString;

public import pham.utl.utl_result : ResultIf;

struct NamedValue(S)
{
    S name;
    S value;
}

/**
 * Returns the class-name of object. If it is null, returns "null"
 * Params:
 *   object = the object to get the class-name from
 */
string className(const(Object) object) nothrow pure @safe
{
    return object is null ? "null" : typeid(object).name;
}

string concateLineIf(string lines, string addedLine) nothrow @safe
{
    if (addedLine.length == 0)
        return lines;
    else if (lines.length == 0)
        return addedLine;
    else
        return lines ~ "\n" ~ addedLine;
}

ResultIf!(Char[]) decodeFormValue(Char)(return Char[] encodedFormValue,
    const(Char) invalidReplacementChar = '?') nothrow pure @safe
if (isSomeChar!Char)
{
    import pham.utl.utl_array_append : Appender;
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseHexDigits;

    if (encodedFormValue.simpleIndexOfAny("%+") < 0)
        return ResultIf!(Char[]).ok(encodedFormValue);

    Char[] firstErrorText;
    ptrdiff_t firstErrorIndex = -1;

    auto result = Appender!(Char[])(encodedFormValue.length);

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
                    if (parseHexDigits(encodedFormValue[i..(i + 2)], h) == NumericParsedKind.ok)
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
        ? ResultIf!(Char[]).ok(result.data)
        : ResultIf!(Char[]).error(result.data, cast(int)firstErrorIndex, "Invalid form-encoded character: " ~ firstErrorText.idup);
}

ptrdiff_t indexOf(S)(scope const(NamedValue!S)[] values, scope const(S) name) nothrow pure @safe
{
    foreach (i, ref v; values)
    {
        if (v.name == name)
            return i;
    }
    return -1;
}

/**
 * Returns true if all characters `chars` are in the range 0..0x7F
 * Params:
 *   chars = the list of characters to test
 */
bool isAllSimpleChar(scope const(char)[] chars) @nogc nothrow pure @safe
{
    foreach (i; 0..chars.length)
    {
        if (!isSimpleChar(chars[i]))
            return false;
    }
    return true;
}

/**
 * Returns true if `c` is in the range 0..0x7F
 * Params:
 *   c = the character to test
 */
pragma(inline, true)
bool isSimpleChar(const(char) c) @nogc nothrow pure @safe
{
    return c <= 0x7F;
}

/**
 * Pads the string `value` with character `c` if `value.length` is shorter than `size`
 * Params:
 *   value = the string value to be checked and padded
 *   size = max length to be checked against value.length
 *          a positive value will do a left padding
 *          a negative value will do a right padding
 *   c = a character used for padding
 * Returns:
 *   a string with proper padded character(s)
 */
S pad(S, Char)(S value, const(ptrdiff_t) size, Char c) nothrow pure @safe
if (isSomeString!S && isSomeChar!Char && is(Unqual!(typeof(S.init[0])) == Char))
{
    import std.math : abs;

    const n = abs(size);
    if (value.length >= n)
        return value;

    return size > 0
        ? (stringOfChar!Char(n - value.length, c) ~ value)
        : (value ~ stringOfChar!Char(n - value.length, c));
}

ref Writer padRight(Char, Writer)(return ref Writer sink, const(size_t) length, const(size_t) size, Char c) nothrow pure @safe
if (isSomeChar!Char)
{
    return length >= size
        ? sink
        : stringOfChar!(Char, Writer)(sink, size - length, c);
}

void parseFormEncodedValues(Char)(return Char[] formEncodedValues,
    bool delegate(size_t index, return ResultIf!(Char[]) name, return ResultIf!(Char[]) value) nothrow @safe valueCallBack,
    const(Char) invalidReplacementChar = '?') nothrow @safe
if (isSomeChar!Char)
{
    size_t counter;
    foreach (formEncodedValue; formEncodedValues.simpleSplitter("&;"))
    {
        const i = formEncodedValue.simpleIndexOf('=');
        if (i >= 0)
        {
            if (!valueCallBack(counter++,
                    decodeFormValue!Char(formEncodedValue[0..i], invalidReplacementChar),
                    decodeFormValue!Char(formEncodedValue[(i + 1)..$], invalidReplacementChar)))
                break;
        }
        else
        {
            if (!valueCallBack(counter++,
                    decodeFormValue!Char(formEncodedValue, invalidReplacementChar),
                    ResultIf!(Char[]).ok(null)))
                break;
        }
    }
}

/**
 * Returns the complete class-name of 'object' without template type if any. If `object` is null, returns "null"
 * Params:
 *   object = the object to get the class-name from
 */
string shortClassName(const(Object) object, uint parts = 2) nothrow pure @safe
{
    return object is null
        ? "null"
        : shortenTypeNameTemplate(typeid(object).name).shortenTypeNameModule(parts);
}

string shortFunctionName(uint parts = 2, string fullName = __FUNCTION__) nothrow pure @safe
{
    return shortenTypeNameTemplate(fullName).shortenTypeNameModule(parts);
}

/**
 * Returns the complete aggregate-name of a class/struct without template type
 */
string shortTypeName(T)(uint parts = 2) nothrow @safe
if (is(T == class) || is(T == struct))
{
    return shortenTypeNameTemplate(typeid(T).name).shortenTypeNameModule(parts);
}

string shortenTypeNameModule(string fullName, uint parts = 2) nothrow pure @safe
{
    import std.array : split;

    string result;
    auto nameParts = split(fullName, ".");
    while (nameParts.length && parts--)
    {
        if (result.length)
            result = nameParts[$-1] ~ "." ~ result;
        else
            result = nameParts[$-1];
        nameParts = nameParts[0..$-1];
    }
    return result;
}

/**
 * Strip out the template type if any and returns it
 * Params:
 *   fullName = the complete type name
 */
string shortenTypeNameTemplate(string fullName) nothrow pure @safe
{
    import std.algorithm.iteration : filter;
    import std.array : join, split;
    import std.string : indexOf;

    return split(fullName, ".").filter!(e => e.indexOf('!') < 0).join(".");
}

/**
 * Returns FormatSpec!char with `f` format specifier
 * Params:
 *   precision = optional precision of formated string
 *   width = optional width of formated string
 */
FormatSpec!Char simpleFloatFmt(Char = char)(int precision = -1, int width = 0) nothrow pure @safe
if (isSomeChar!Char)
{
    auto result = FormatSpec!Char("");
    result.spec = 'f';
    result.flDash = true;
    if (precision != -1)
        result.precision = precision;
    if (width != 0)
        result.width = width;
    return result;
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
ptrdiff_t simpleIndexOf(Char)(scope const(Char)[] str, const(Char) c) @nogc nothrow pure @safe
if (isSomeChar!Char)
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
ptrdiff_t simpleIndexOf(Char)(scope const(Char)[] str, scope const(Char)[] subStr) @nogc nothrow pure @safe
if (isSomeChar!Char)
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
ptrdiff_t simpleIndexOfAny(Char)(scope const(Char)[] str, scope const(Char)[] chars) @nogc nothrow pure @safe
if (isSomeChar!Char)
{
	foreach (i; 0..str.length)
    {
		if (simpleIndexOf(chars, str[i]) >= 0)
			return i;
    }
	return -1;
}

/**
 * Returns FormatSpec!char with `d` format specifier
 * Params:
 *   width = optional width of formated string
 */
FormatSpec!Char simpleIntegerFmt(Char = char)(int width = 0) nothrow pure @safe
if (isSomeChar!Char)
{
    auto result = FormatSpec!Char("");
    result.spec = 'd';
    if (width != 0)
        result.width = width;
    return result;
}

auto simpleSplitter(S, Separator)(S str, Separator separator) nothrow @safe
{
    static struct Result
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

/**
 * Returns a string with length `count` with specified character `c`
 * Params:
 *   count = number of characters
 *   c = expected string of character
 */
auto stringOfChar(Char = char)(size_t count, Char c) nothrow pure @trusted
if (is(Unqual!Char == char) || is(Unqual!Char == wchar) || is(Unqual!Char == dchar))
{
    auto result = new Unqual!Char[](count);
    result[] = c;
    static if (is(Unqual!Char == char))
        return cast(string)result;
    else static if (is(Unqual!Char == wchar))
        return cast(wstring)result;
    else
        return cast(dstring)result;
}

ref Writer stringOfChar(Char = char, Writer)(return ref Writer sink, size_t count, Char c) nothrow pure @safe
if (isSomeChar!Char)
{
    while (count)
    {
        sink.put(c);
        count--;
    }
    return sink;
}

ref Writer stringOfNumber(Writer, T, Char = char)(return ref Writer sink, T number, scope auto ref FormatSpec!Char spec) pure @safe
if ((isFloatingPoint!T || isIntegral!T) && isSomeChar!Char)
{
    import std.format.write : formatValue;

    formatValue(sink, number, spec);
    return sink;
}

Char[] stringOfNumber(T, Char = char)(return scope Char[] buffer, T number, scope auto ref FormatSpec!Char spec) pure @safe
if ((isFloatingPoint!T || isIntegral!T) && isSomeChar!Char)
{
    static struct Sink
    {
        Char[] buf;
        size_t i;

        void put(Char c)
        {
            assert(i < buf.length);

            buf[i] = c;
            i++;
        }

        void put(scope const(Char)[] s)
        {
            assert(i + s.length < buf.length);

            buf[i..i + s.length] = s[];
            i += s.length;
        }
    }

    auto sink = Sink(buffer);
    stringOfNumber(sink, number, spec);
    return buffer[0..sink.i];
}

S valueOf(S)(NamedValue!S[] values, scope const(S) name, S notFound = S.init) nothrow pure @safe
{
    foreach (ref v; values)
    {
        if (v.name == name)
            return v.value;
    }
    return notFound;
}


private:

version(unittest)
{
    class TestClassName
    {
        string testFN() nothrow @safe
        {
            return __FUNCTION__;
        }
    }

    class TestClassTemplate(T) {}

    struct TestStructName
    {
        string testFN() nothrow @safe
        {
            return __FUNCTION__;
        }
    }

    string testFN() nothrow @safe
    {
        return __FUNCTION__;
    }
}

nothrow @safe unittest // className
{
    auto c1 = new TestClassName();
    assert(className(c1) == "pham.utl.utl_text.TestClassName");

    auto c2 = new TestClassTemplate!int();
    assert(className(c2) == "pham.utl.utl_text.TestClassTemplate!int.TestClassTemplate");
}

nothrow @safe unittest // concateLineIf
{
    assert(concateLineIf("", "") == "");
    assert(concateLineIf("a", "") == "a");
    assert(concateLineIf("", "bc") == "bc");
    assert(concateLineIf("a", "bc") == "a\nbc");
}

nothrow @safe unittest // decodeFormValue
{
    assert(decodeFormValue("Hello World", '\0') == "Hello World");
    assert(decodeFormValue("%0D%0a", '\0') == "\r\n");
	assert(decodeFormValue("%c2%aE", '\0') == "®");
	assert(decodeFormValue("This+is%20a+test", '\0') == "This is a test");
    assert(decodeFormValue("This~is%20a-test%21%0D%0AHello%2C%20W%C3%B6rld..%20", '\0') == "This~is a-test!\r\nHello, Wörld.. ");

    assert(decodeFormValue("Hello+%x2orld", '?') == "Hello ?orld");
    assert(decodeFormValue("Hello+Worl%", '?') == "Hello Worl?");
}

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

nothrow @safe unittest // pad
{
    assert(pad("", 2, ' ') == "  ");
    assert(pad("12", 2, ' ') == "12");
    assert(pad("12", 3, ' ') == " 12");
    assert(pad("12", -3, ' ') == "12 ");
}

nothrow @safe unittest // padRight
{
    import std.array : Appender;

    Appender!(char[]) s;
    assert(padRight(s, s.data.length, 2, ' ').data == "  ");

    s.clear();
    s.put("12");
    assert(padRight(s, s.data.length, 2, ' ').data == "12");

    s.clear();
    s.put("12");
    assert(padRight(s, s.data.length, 3, ' ').data == "12 ");
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
    parseFormEncodedValues!(immutable(char))("a=b;c;dee=asd&e=fgh&f=j%20l", &parsedValue);
    assert("a" in values && values["a"] == "b");
	assert("c" in values && values["c"] == "");
	assert("dee" in values && values["dee"] == "asd");
	assert("e" in values && values["e"] == "fgh");
	assert("f" in values && values["f"] == "j l");
}

nothrow @safe unittest // shortClassName
{
    auto c1 = new TestClassName();
    assert(shortClassName(c1) == "utl_text.TestClassName");

    auto c2 = new TestClassTemplate!int();
    assert(shortClassName(c2) == "utl_text.TestClassTemplate");
}

nothrow @safe unittest // shortFunctionName
{
    static void testSelf()
    {
        assert(shortFunctionName(1) == "testSelf");
    }

    static immutable sample = "pham.db.db_fbdatabase.FbService.traceStart";
    assert(shortFunctionName(0, sample).length == 0);
    assert(shortFunctionName(1, sample) == "traceStart");
    assert(shortFunctionName(2, sample) == "FbService.traceStart");
    assert(shortFunctionName(3, sample) == "db_fbdatabase.FbService.traceStart");
    assert(shortFunctionName(4, sample) == "db.db_fbdatabase.FbService.traceStart");
    assert(shortFunctionName(5, sample) == sample);
    assert(shortFunctionName(6, sample) == sample);

    testSelf();
}

nothrow @safe unittest // shortTypeName
{
    //import std.stdio : writeln; debug writeln(typeid(TestClassTemplate!int).name);

    assert(shortTypeName!TestClassName() == "utl_text.TestClassName", shortTypeName!TestClassName());
    assert(shortTypeName!(TestClassTemplate!int)() == "utl_text.TestClassTemplate", shortTypeName!(TestClassTemplate!int)());
    assert(shortTypeName!TestStructName() == "utl_text.TestStructName", shortTypeName!TestStructName());
}

nothrow @safe unittest // shortenTypeNameModule
{
    assert(shortenTypeNameModule("pham.utl.utl_text.TestType") == "utl_text.TestType", shortenTypeNameModule("pham.utl.utl_text.TestType"));
    assert(shortenTypeNameModule("pham.utl.utl_text.TestTemplate!int.TestClassName") == "TestTemplate!int.TestClassName", shortenTypeNameModule("pham.utl.utl_text.TestTemplate!int.TestClassName"));
}

nothrow @safe unittest // shortenTypeNameTemplate
{
    assert(shortenTypeNameTemplate("utl_text.TestClassName") == "utl_text.TestClassName");
    assert(shortenTypeNameTemplate("utl_text.TestClassTemplate!int.TestClassTemplate") == "utl_text.TestClassTemplate");
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

nothrow @safe unittest // stringOfChar (string)
{
    assert(stringOfChar(4, ' ') == "    ");
    assert(stringOfChar(0, ' ').length == 0);
}

nothrow @safe unittest // stringOfChar (Writer)
{
    import std.array : Appender;

    Appender!(char[]) s;
    assert(stringOfChar(s, 4, ' ').data == "    ");

    s.clear();
    assert(stringOfChar(s, 0, ' ').data.length == 0);
}

unittest // stringOfNumber
{
    char[50] buffer;

    assert(stringOfNumber(buffer[], 0, simpleIntegerFmt()) == "0");
    assert(stringOfNumber(buffer[], 1, simpleIntegerFmt()) == "1");
    assert(stringOfNumber(buffer[], int.min, simpleIntegerFmt()) == "-2147483648");
    assert(stringOfNumber(buffer[], int.max, simpleIntegerFmt()) == "2147483647");

    assert(stringOfNumber(buffer[], 0.0, simpleFloatFmt(10)) == "0.0000000000");
    assert(stringOfNumber(buffer[], 1.0, simpleFloatFmt(10)) == "1.0000000000");
    assert(stringOfNumber(buffer[], 0.1, simpleFloatFmt(10)) == "0.1000000000", stringOfNumber(buffer[], 0.1, simpleFloatFmt(10)).idup);
    assert(stringOfNumber(buffer[], -0.1, simpleFloatFmt(10)) == "-0.1000000000", stringOfNumber(buffer[], -0.1, simpleFloatFmt(10)).idup);
}
