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

struct NamedValue(String = string)
{
    String name;
    String value;
}

/**
 * Returns true if `startWidth` is starting with `startWidth`
 * ignoring the case of the strings
 * Params:
 *  s1 = a string that being looked into
 *  startWidth = a substring to compare for start with
 */
pragma(inline, true)
bool caseInsentiveStartWidth(scope const(char)[] s1, scope const(char)[] startWidth) nothrow pure @safe
{
    import std.uni : sicmp;

    return s1.length >= startWidth.length
        && sicmp(s1[0..startWidth.length], startWidth) == 0;
}

/**
 * Returns the class-name of object. If it is null, returns "null"
 * Params:
 *  object = the object to get the class-name from
 */
string className(const(Object) object) nothrow pure @safe
{
    return object is null ? "null" : typeid(object).name;
}

string concateLineIf(string lines, string addingLine) nothrow @safe
{
    import std.ascii : newline;

    if (addingLine.length == 0)
        return lines;
    else if (lines.length == 0)
        return addingLine;
    else
        return lines ~ newline ~ addingLine;
}

ResultIf!(Char[]) decodeFormValue(Char = char)(return Char[] encodedFormValue,
    const(Char) invalidReplacementChar = '?') nothrow pure @safe
if (isSomeChar!Char)
{
    import pham.utl.utl_array_append : Appender;
    import pham.utl.utl_numeric_parser : NumericParsedKind, parseHexDigits;

    if (!encodedFormValue.simpleIndexOfAny("%+").found)
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

ptrdiff_t indexOf(String = string)(scope const(NamedValue!String)[] values, scope const(String) name) nothrow pure @safe
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
bool isAllSimpleChar(Char = char)(scope const(Char)[] chars) @nogc nothrow pure @safe
if (isSomeChar!Char || isIntegral!Char)
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
 *  c = the character to test
 */
pragma(inline, true)
bool isSimpleChar(Char = char)(const(Char) c) @nogc nothrow pure @safe
if (isSomeChar!Char || isIntegral!Char)
{
    return c <= 0x7F;
}

/**
 * Returns true if `c` is a digit (0..9).
 * Params:
 *   c = the character to test
 */
pragma(inline, true)
bool isSimpleDigit(const(dchar) c) @nogc nothrow pure @safe
{
    return '0' <= c && c <= '9';
}

/**
 * Returns true if `c` is a digit in base 16 (0..9, A..F, a..f)
 * Params:
 *  c = the character to test
 */
pragma(inline, true)
bool isSimpleHexDigit(const(dchar) c) @nogc nothrow pure @safe
{
    const hc = c | 0x20;
    return ('0' <= c && c <= '9') || ('a' <= hc && hc <= 'f');
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
String pad(String, Char)(String value, const(ptrdiff_t) size, Char c) nothrow pure @safe
if (isSomeString!String && isSomeChar!Char && is(Unqual!(typeof(String.init[0])) == Char))
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

void parseFormEncodedValues(Char = char)(return Char[] formEncodedValues,
    bool delegate(size_t count, return ResultIf!(Char[]) name, return ResultIf!(Char[]) value) nothrow @safe valueCallBack,
    const(Char) invalidReplacementChar = '?') nothrow @safe
if (isSomeChar!Char)
{
    size_t counter;
    foreach (formEncodedValue; formEncodedValues.simpleSplitter("&;"))
    {
        //import std.stdio : writeln; debug writeln("counter=", counter, ", formEncodedValue=", formEncodedValue);

        counter++;

        if (formEncodedValue.length == 0)
        {
            if (!valueCallBack(counter,
                    ResultIf!(Char[]).error(-1, null),
                    ResultIf!(Char[]).error(-1, null)))
                break;
            continue;
        }

        auto pair = formEncodedValue.simpleSplitter('=').pair();
        if (!valueCallBack(counter,
                decodeFormValue!Char(pair.name, invalidReplacementChar),
                decodeFormValue!Char(pair.value, invalidReplacementChar)))
            break;
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
 * Count the occurrence of element `c` in an element array `str` and returns the number of matched elements found
 * Params:
 *  str = element array
 *  c = an element to count of
 */
size_t simpleCount(E = char)(scope const(E)[] str, const(E) c) nothrow pure @safe
if (isSomeChar!E || isIntegral!E)
{
    size_t result;
    foreach (i; 0..str.length)
    {
        if (str[i] == c)
            result++;
    }
    return result;
}

/**
 * Returns true if str is ending with `c`
 * Params:
 *  str = a character/element array to look into
 *  c = a character/element to test
 */
pragma(inline, true)
bool simpleEndWith(E = char)(scope const(E)[] str, const(E) c) @nogc nothrow pure @safe
if (isSomeChar!E || isIntegral!E)
{
    return str.length && str[$ - 1] == c;
}

/**
 * Returns index of matched element of `cs` if str is ending with one of `cs` element
 * -1 is returned if there is no matched
 * Params:
 *  str = a character/element array to look into
 *  cs = any characters/elements to test for
 */
ptrdiff_t simpleEndWithAny(E = char)(scope const(E)[] str, scope const(E)[] cs) @nogc nothrow pure @safe
if (isSomeChar!E || isIntegral!E)
{
    if (str.length == 0 || cs.length == 0)
        return -1;

    const end = str[$ - 1];
	foreach (i; 0..cs.length)
    {
		if (end == cs[i])
			return i;
    }

	return -1;
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
 * Finds the first occurence of element `c` in an element array `str` and returns matched index.
 * For a string, no auto decode
 * Params:
 *   str = element array
 *   c = an element to look for
 * Returns:
 *   index of `c` in `str` if found
 *   -1 if not found
 */
ptrdiff_t simpleIndexOf(E = char)(scope const(E)[] str, const(E) c, size_t fromIndex = 0) @nogc nothrow pure @safe
if (isSomeChar!E || isIntegral!E)
{
    if (fromIndex >= str.length)
        return -1;

	foreach (i; fromIndex..str.length)
    {
		if (str[i] == c)
			return i;
    }

	return -1;
}

/**
 * Finds the first occurence of sub-element array `subStr` in element array `str` and returns matched index.
 * For a string, no auto decode
 * Params:
 *   str = element array
 *   subStr = a sub-element array to look for
 * Returns:
 *   index of `subStr` in `str` if found
 *   -1 if not found
 */
ptrdiff_t simpleIndexOf(E = char)(scope const(E)[] str, scope const(E)[] subStr, size_t fromIndex = 0) @nogc nothrow pure @safe
if (isSomeChar!E || isIntegral!E)
{
    if (fromIndex >= str.length || str.length - fromIndex < subStr.length || subStr.length == 0)
        return -1;

    const c0 = subStr[0];
	foreach (i; fromIndex..(str.length - subStr.length + 1))
    {
		if (str[i] != c0)
            continue;

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
	return -1;
}

/**
 * Finds the first occurence of any element of `chars` in `str` and returns its index.
 * For a string, no auto decode
 * Params:
 *   str = element array
 *   chars = list of elements to look for
 * Returns:
 *   pair of indexes where SimpleIndexOfAny.index = found index in str and SimpleIndexOfAny.indexOfChar = index of chars
 *   SimpleIndexOfAny.index = -1 and SimpleIndexOfAny.indexOfChar = -1 if not found
 */
struct SimpleIndexOfAny
{
nothrow @safe:

    ptrdiff_t index;
    ptrdiff_t indexOfChar;

    bool opCast(C: bool)() const pure
    {
        return found;
    }

    string toString() const pure
    {
        import std.conv : text;

        return text(index, ":", indexOfChar);
    }

    pragma(inline, true)
    @property bool found() const pure
    {
        return index >= 0;
    }
}
SimpleIndexOfAny simpleIndexOfAny(E = char)(scope const(E)[] str, scope const(E)[] chars, size_t fromIndex = 0) @nogc nothrow pure @safe
if (isSomeChar!E || isIntegral!E)
{
    if (fromIndex >= str.length || chars.length == 0)
        return SimpleIndexOfAny(-1, -1);

	foreach (i; fromIndex..str.length)
    {
        const c = str[i];
        foreach (j; 0..chars.length)
        {
            if (chars[j] == c)
                return SimpleIndexOfAny(i, j);
        }
    }

	return SimpleIndexOfAny(-1, -1);
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

auto simpleSplitter(String = string, Separator = char)(String str, Separator separator) nothrow @safe
{
    static struct RangeResult
    {
    nothrow @safe:

    public:
        this(String input, Separator separator)
        {
            this._input = input;
            this._separator = separator;
            this._frontLength = input.length == 0 ? atEnd : unComputed;
        }

        NamedValue!String pair() return scope
        in
        {
            assert(!empty, "Attempting to fetch the name-value pair of an empty simpleSplitter.");
        }
        do
        {
            auto name = front;
            popFront();
            if (empty)
                return NamedValue!String(name, null);

            auto value = front;
            popFront();
            return NamedValue!String(name, value);
        }

        void popFront() scope
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

        @property bool empty() const @nogc scope
        {
            return _frontLength == atEnd;
        }

        @property String front() return scope
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
        void computeFrontLength() @nogc scope
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
        bool isSeparator(const(size_t) i) const @nogc scope
        {
            static if (isSomeChar!Separator)
                return _input[i] == _separator;
            else
                return _separator.simpleIndexOf(_input[i]) >= 0;
        }

    private:
        enum size_t unComputed = size_t.max - 1, atEnd = size_t.max;

        String _input;
        size_t _frontLength;
        Separator _separator;
    }

    return RangeResult(str, separator);
}

bool simpleStartWith(E = char)(scope const(E)[] str, scope const(E)[] chars) @nogc nothrow pure @safe
if (isSomeChar!E || isIntegral!E)
{
    return str.length >= chars.length && chars.length != 0
        ? str[0..chars.length] == chars
        : false;
}

String simpleTrim(String = string)(return String str) nothrow @safe
{
    return str.simpleTrimLeft().simpleTrimRight();
}

String simpleTrimLeft(String = string)(return String str) nothrow @safe
{
    while (str.length && str[0] <= ' ')
        str = str[1..$];
    return str;
}

String simpleTrimRight(String = string)(return String str) nothrow @safe
{
    while (str.length && str[$ - 1] <= ' ')
        str = str[0..$ - 1];
    return str;
}

String toString(String = string)(const(NamedValue!String) nv) nothrow @safe
{
    return nv.name ~ "=" ~ nv.value;
}

String toString(String = string)(const(NamedValue!String)[] nvs) nothrow @safe
{
    if (nvs.length == 0)
        return "[]";

    String result = "[" ~ nvs[0].name ~ "=" ~ nvs[0].value;
    foreach (ref nv; nvs[1..$])
    {
        result ~= ", " ~ nv.name ~ "=" ~ nv.value;
    }
    return result ~ "]";
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

ref Writer stringOfNumber(Writer, T, Char = char)(return ref Writer sink, T number) nothrow pure @safe
if ((isFloatingPoint!T || isIntegral!T) && isSomeChar!Char)
{
    import std.format.write : formatValue;

    scope (failure) assert(0, "Assume nothrow failed");

    static immutable spec = simpleIntegerFmt!Char();
    formatValue(sink, number, spec);
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

String valueOf(String = string)(NamedValue!String[] values, scope const(String) name,
    String notFound = null) nothrow pure @safe
if (isSomeString!String)
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
    import std.ascii : newline;

    assert(concateLineIf("", "") == "");
    assert(concateLineIf("a", "") == "a");
    assert(concateLineIf("", "bc") == "bc");
    assert(concateLineIf("a", "bc") == "a" ~ newline ~ "bc");
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

    bool parsedValue(size_t count, ResultIf!string name, ResultIf!string value) nothrow @safe
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

nothrow @safe unittest // simpleCount
{
    assert("".simpleCount('=') == 0);
    assert("abc".simpleCount('=') == 0);
    assert("abc=123".simpleCount('=') == 1);
    assert("abc=123=xy".simpleCount('=') == 2);
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
    assert(simpleIndexOfAny(s, "xW").index == 6, simpleIndexOfAny(s, "rW").toString());
    assert(simpleIndexOfAny(s, "or").index == 4, simpleIndexOfAny(s, "or").toString());
    assert(simpleIndexOfAny(s, "zx").index == -1, simpleIndexOfAny(s, "zx").toString());
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

    auto nv = "ab=123".simpleSplitter('=');
    assert(nv.pair() == NamedValue!string("ab", "123"));

    nv = "ab=".simpleSplitter('=');
    assert(nv.pair() == NamedValue!string("ab", ""));

    nv = "ab".simpleSplitter('=');
    assert(nv.pair() == NamedValue!string("ab", null));

    assert("".simpleSplitter("?|").equal(empty));
    assert("|".simpleSplitter("?|").equal(["", ""]));
    assert("||".simpleSplitter("?|").equal(["", "", ""]));
    assert("|a|bc|def|".simpleSplitter("?|").equal(["", "a", "bc", "def", ""]));
    assert("a|bc|def".simpleSplitter("?|").equal(["a", "bc", "def"]));
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
    char[50] buffer = 0;

    assert(stringOfNumber(buffer[], 0, simpleIntegerFmt()) == "0");
    assert(stringOfNumber(buffer[], 1, simpleIntegerFmt()) == "1");
    assert(stringOfNumber(buffer[], int.min, simpleIntegerFmt()) == "-2147483648");
    assert(stringOfNumber(buffer[], int.max, simpleIntegerFmt()) == "2147483647");

    assert(stringOfNumber(buffer[], 0.0, simpleFloatFmt(10)) == "0.0000000000");
    assert(stringOfNumber(buffer[], 1.0, simpleFloatFmt(10)) == "1.0000000000");
    assert(stringOfNumber(buffer[], 0.1, simpleFloatFmt(10)) == "0.1000000000", stringOfNumber(buffer[], 0.1, simpleFloatFmt(10)).idup);
    assert(stringOfNumber(buffer[], -0.1, simpleFloatFmt(10)) == "-0.1000000000", stringOfNumber(buffer[], -0.1, simpleFloatFmt(10)).idup);
}

@nogc nothrow pure @safe unittest // isSimpleDigit
{
    static immutable string fullDigits  = "0123456789";
    foreach (i; 0..fullDigits.length)
        assert(isSimpleDigit(fullDigits[i]));

    assert(!isSimpleDigit('B'));
    assert(!isSimpleDigit('#'));

    // N.B.: does not return true for non-ASCII Unicode numbers
    assert(!isSimpleDigit('\uFF10')); // full-width digit zero (U+FF10)
    assert(!isSimpleDigit('\uFF14')); // full-width digit four (U+FF14)
}

@nogc nothrow pure @safe unittest // isSimpleHexDigit
{
    static immutable string fullHexDigits  = "0123456789ABCDEFabcdef";
    foreach (i; 0..fullHexDigits.length)
        assert(isSimpleHexDigit(fullHexDigits[i]));

    assert(!isSimpleHexDigit('\uFF10')); // full-width digit zero (U+FF10)
    assert(!isSimpleHexDigit('\uFF14')); // full-width digit four (U+FF14)
    assert(!isSimpleHexDigit('g'));
    assert(!isSimpleHexDigit('G'));
    assert(!isSimpleHexDigit('#'));
}

@nogc nothrow pure @safe unittest // simpleEndWith
{
    assert("abc".simpleEndWith('c'));
    assert(!"abc".simpleEndWith('a'));
    assert(!"abc".simpleEndWith('b'));
    assert(!"".simpleEndWith('a'));
}

@nogc nothrow pure @safe unittest // simpleEndWithAny
{
    assert("abc".simpleEndWithAny("c") == 0);
    assert("abc".simpleEndWithAny("dc") == 1);
    assert("abc".simpleEndWithAny("ab") == -1);
    assert("".simpleEndWithAny("a") == -1);
}

unittest // toString
{
    NamedValue!string v;
    v.name = "name";
    v.value = "value";
    assert(v.toString() == "name=value");

    v.name = "namE";
    v.value = "";
    assert(v.toString() == "namE=");
    
    NamedValue!string[] vs;
    vs = [NamedValue!string("name", "value"), NamedValue!string("namE", "")];
    assert(vs.toString() == "[name=value, namE=]");
    
    vs = null;
    assert(vs.toString() == "[]");
}
