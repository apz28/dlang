/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2026 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.utl.utl_html;

import std.uni : sicmp;

debug(debug_pham_utl_utl_html) import std.stdio : writeln;
import pham.utl.utl_array_append : Appender;
import pham.utl.utl_result : ResultIf;
public import pham.utl.utl_text : NamedValue;
import pham.utl.utl_utf8 : replacementUtf8Char;

@safe:

immutable string htmlNewline = "\x0D\x0A"; // Must use this format

/**
 * HTML reserved chars
 * '&' = '&amp;'
 * '<' = '&lt;'
 * '>' = '&gt;'
 * '"' = '&quot;'
 * ''' = '&apos;'
 * &#nnnn; or &#xhhhh;
 */
enum ampChar = '&';
enum ltChar = '<';
enum gtChar = '>';
enum dquotChar = '"';
enum squotChar = '\'';
enum ctrlMax = 31;

immutable string ampStr = "&amp;";
immutable string ltStr = "&lt;";
immutable string gtStr = "&gt;";
immutable string dquotStr = "&quot;";
immutable string squotStr = "&apos;";

enum HtmlEncodeChar : ubyte
{
    none,
    amp,
    lt,
    gt,
    dquot,
    squot,
    ctrl,
}

struct URL
{
    static immutable string httpScheme = "http://";
    static immutable string httpsScheme = "https://";

nothrow @safe:

    /// The URL scheme. For instance, ssh, ftp, or https.
	string scheme;

	/// The hostname.
	string host;

    string port;

	/// The username in this URL. Usually absent. If present, there will also be a password.
	string user;

	/// The password in this URL. Usually absent.
	string password;

    string path;

    NamedValue!string[] params;

    string fragment;

    pragma(inline, true)
    bool isValid() const pure
    {
        return host.length != 0
            && (port.length == 0 || isValidPort());
    }

    // Fully Qualified Domain Name
    bool isValidFQDN() const pure
    {
        import pham.utl.utl_text : simpleIndexOf;

        return isValid() && (host.simpleIndexOf('.') > 0);
    }

    bool isValidPort() const pure
    {
        import pham.utl.utl_text : isSimpleDigit;

        // 65000 - Max of 5 digits
        if (port.length == 0 || port.length > 5)
            return false;

        foreach (i; 0..port.length)
        {
            if (!isSimpleDigit(port[i]))
                return false;
        }

        return true;
    }

    void reset() pure
    {
        scheme = host = port = user = password = path = fragment = null;
        params = null;
    }
}

HtmlEncodeChar htmlEncode(const(dchar) c) @nogc nothrow pure
{
    if (c == ampChar)
        return HtmlEncodeChar.amp;
    else if (c == ltChar)
        return HtmlEncodeChar.lt;
    else if (c == gtChar)
        return HtmlEncodeChar.gt;
    else if (c == dquotChar)
        return HtmlEncodeChar.dquot;
    else if (c == squotChar)
        return HtmlEncodeChar.squot;
    else if (c <= ctrlMax)
        return HtmlEncodeChar.ctrl;
    else
        return HtmlEncodeChar.none;
}

string htmlEncode(string str) nothrow pure
{
    import std.algorithm.comparison : min;
    import pham.utl.utl_utf8 : nextUTF8Char;

    if (str.length == 0)
        return null;

    // Loop through to see encoding needed
    dchar c;
    size_t p;
    while (p < str.length)
    {
        const p2 = p;
        if (!nextUTF8Char(str, p, c))
            c = replacementUtf8Char;

        if (htmlEncode(c) != HtmlEncodeChar.none)
        {
            p = p2;
            break;
        }
    }
    if (p >= str.length)
        return str;

    // There is character needs to be encoded
    auto result = Appender!string(str.length + min(str.length / 4, 500));
    result.put(str[0..p]);
    return result.htmlEncode(str[p..$]).data;
}

ref Output htmlEncode(Output)(return ref Output output, scope const(char)[] str) nothrow pure
{
    import pham.utl.utl_text : simpleIntegerFmt, stringOfNumber;
    import pham.utl.utl_utf8 : nextUTF8Char;

    dchar c;
    size_t p;

    while (p < str.length)
    {
        if (!nextUTF8Char(str, p, c))
            c = replacementUtf8Char;

        final switch (htmlEncode(c))
        {
            case HtmlEncodeChar.none:
                output.put(c);
                break;

            case HtmlEncodeChar.amp:
                output.put(ampStr);
                break;

            case HtmlEncodeChar.lt:
                output.put(ltStr);
                break;

            case HtmlEncodeChar.gt:
                output.put(gtStr);
                break;

            case HtmlEncodeChar.dquot:
                output.put(dquotStr);
                break;

            case HtmlEncodeChar.squot:
                output.put(squotStr);
                break;

            case HtmlEncodeChar.ctrl:
                static assert(dchar.sizeof == int.sizeof);
                output.put("&#");
                output.stringOfNumber(cast(int)c);
                output.put(';');
                break;
        }
    }

    return output;
}

/* WK = well-known
/* We support both well-known suffixes defined by RFC 8414. */
immutable string oauthWKPrefix = "/.well-known/";
immutable string oauthWKSuffix = "oauth-authorization-server";
immutable string openIdWKSuffix = "openid-configuration";
ResultIf!string authIssuerFromWellKnownUri(string wkUri, int errorCode = -1) nothrow pure
{
    import std.ascii : newline;
    import std.conv : text;
    import pham.utl.utl_text : caseInsentiveStartWidth, simpleIndexOf, simpleIndexOfAny;

    string authorityScheme;
    string authorityStart;

    /*
     * "https://" is required for issuer identifiers (RFC 8414, Sec. 2; OIDC
     * Discovery 1.0, Sec. 3)
     */
    if (wkUri.caseInsentiveStartWidth(URL.httpsScheme))
    {
        authorityStart = wkUri[URL.httpsScheme.length..$];
        authorityScheme = URL.httpsScheme;
    }

    /* Allow "http://" for testing only */
    version(unittest)
    {
        if (authorityStart.length == 0 && wkUri.caseInsentiveStartWidth(URL.httpScheme))
        {
            authorityStart = wkUri[URL.httpScheme.length..$];
            authorityScheme = URL.httpScheme;
        }
    }

    if (authorityStart.length == 0)
    {
        auto msg = text("OAuth discovery URI must use HTTPS.", newline, wkUri);
        return ResultIf!string.error(errorCode, msg);
    }

    /*
     * Well-known URIs in general may support queries and fragments, but the
     * two types we support here do not. (They must be constructed from the
     * components of issuer identifiers, which themselves may not contain any
     * queries or fragments.)
     */
    if (authorityStart.simpleIndexOfAny("?#").found)
    {
        debug(debug_pham_utl_utl_html) debug writeln("authorityStart=", authorityStart);
        auto msg = text("OAuth discovery URI must not contain query or fragment components.", newline, wkUri);
        return ResultIf!string.error(errorCode, msg);
    }

    /*
     * Find the start of the .well-known prefix. IETF rules (RFC 8615) state
     * this must be at the beginning of the path component, but OIDC defined
     * it at the end instead (OIDC Discovery 1.0, Sec. 4), so we have to
     * search for it anywhere.
     */
    const wkStartIndex = authorityStart.simpleIndexOf(oauthWKPrefix);
    if (wkStartIndex < 0)
    {
        auto msg = text("OAuth discovery URI is not a `.well-known` URI.", newline, wkUri);
        return ResultIf!string.error(errorCode, msg);
    }
    const wkStart = authorityStart[wkStartIndex..$];

    /*
     * Now find the suffix type. We only support the two defined in OIDC
     * Discovery 1.0 and RFC 8414.
     */
    auto wkEndIndex = wkStartIndex + oauthWKPrefix.length;
    auto wkEnd = authorityStart[wkEndIndex..$];
    if (wkEnd.caseInsentiveStartWidth(openIdWKSuffix))
    {
        wkEndIndex += openIdWKSuffix.length;
        wkEnd = wkEnd[openIdWKSuffix.length..$];
    }
    else if (wkEnd.caseInsentiveStartWidth(oauthWKSuffix))
    {
        wkEndIndex += oauthWKSuffix.length;
        wkEnd = wkEnd[oauthWKSuffix.length..$];
    }
    else
        wkEndIndex = 0; // Not found

    /*
     * Even if there's a match, we still need to check to make sure the suffix
     * takes up the entire path segment, to weed out constructions like
     * "/.well-known/openid-configuration-bad".
     */
    if (wkEndIndex == 0 || (wkEnd.length != 0 && wkEnd[0] != '/'))
    {
        debug(debug_pham_utl_utl_html) debug writeln("wkEnd=", wkEnd);
        auto msg = text("OAuth discovery URI uses an unsupported `.well-known` suffix.", newline, wkUri);
        return ResultIf!string.error(errorCode, msg);
    }

    /*
     * Finally, make sure the .well-known components are provided either as a
     * prefix (IETF style) or as a postfix (OIDC style). In other words,
     * "https://localhost/a/.well-known/openid-configuration/b" is not allowed
     * to claim association with "https://localhost/a/b".
     *
	 * It's not at the end, so it's required to be at the beginning at the
	 * path. Find the starting slash.
	 */
    if (wkEnd.length)
    {
        const pathStartIndex = authorityStart.simpleIndexOf('/');
        assert(pathStartIndex >= 0); // otherwise we wouldn't have found wkPrefix
        const pathStart = authorityStart[pathStartIndex..$];
        if (pathStart != wkStart)
        {
            debug(debug_pham_utl_utl_html) debug writeln("pathStart=", pathStart, ", wkStart=", wkStart);
            auto msg = text("OAuth discovery URI uses an invalid format.", newline, wkUri);
            return ResultIf!string.error(errorCode, msg);
        }
    }

    /*
     * The .well-known components are from [wk_start, wk_end). Remove those to
     * form the issuer ID, by shifting the path suffix (which may be empty)
     * leftwards.
     */
    debug(debug_pham_utl_utl_html) debug writeln(authorityStart);
    debug(debug_pham_utl_utl_html) debug writeln("wkStartIndex=", wkStartIndex, ", wkEndIndex=", wkEndIndex, ", wkUri.length=", wkUri.length);
    auto issuer = authorityStart[0..wkStartIndex] ~ authorityStart[wkEndIndex..$];
    return ResultIf!string.ok(authorityScheme ~ issuer);
}

bool parseURL(out URL url, string urlString) nothrow pure
{
    import pham.utl.utl_text : simpleIndexOf, simpleIndexOfAny, simpleTrim;

    url.reset();

    urlString = urlString.simpleTrim();
    if (urlString.length == 0)
        return false;

    debug(debug_pham_utl_utl_html) debug writeln("urlString=", urlString);

    // scheme: [//[user:password@] host [:port]] [/] path [?query] [#fragment]

	auto i = urlString.simpleIndexOf("//");
	if (i >= 0)
    {
		if (i > 1)
			url.scheme = urlString[0..i-1];

		urlString = urlString[i+2..$];
        debug(debug_pham_utl_utl_html) debug writeln("after.scheme=", urlString);
	}

    // [user:password@] host [:port] [/] path [?query] [#fragment]
	auto iAny = urlString.simpleIndexOfAny(":/[?");
	if (!iAny.found)
    {
		// Just a hostname.
		url.host = urlString;
		return true;
	}
    // This could be between username and password, or it could be between host and port.
    if (iAny.indexOfChar == 0) // ':'
    {
        const j = urlString.simpleIndexOf('@', iAny.index + 1);
		if (j >= 0)
        {
            url.user = urlString[0..iAny.index];
			url.password = urlString[iAny.index+1..j];
			urlString = urlString[j+1..$];
            debug(debug_pham_utl_utl_html) debug writeln("after.user=", urlString);
		}
    }

    // It's trying to be a host/port, not a user/pass.
	iAny = urlString.simpleIndexOfAny(":/[?");
	if (!iAny.found)
    {
		url.host = urlString;
		return true;
	}

    // Find the hostname. It's either an ipv6 address (which has special rules) or not (which doesn't
	// have special rules). -- The main sticking point is that ipv6 addresses have colons, which we
	// handle specially, and are offset with square brackets.
	if (iAny.indexOfChar == 2) // '['
    {
		const j = urlString.simpleIndexOf(']', iAny.index + 1);
        // unterminated ipv6 address ?
		if (j < 0)
        {
            debug(debug_pham_utl_utl_html) debug writeln("ipv6.failed=", urlString);
			return false;
        }

		// includes square brackets
		url.host = urlString[iAny.index..j+1];
		urlString = urlString[j+1..$];
        debug(debug_pham_utl_utl_html) debug writeln("after.ipv6=", urlString);

        // read to end of string; we finished parse
		if (urlString.length == 0)
			return true;

        const c0 = urlString[0];
		if (c0 != ':' && c0 != '/' && c0 != '?')
        {
            debug(debug_pham_utl_utl_html) debug writeln("ipv6.failed=", urlString);
			return false;
        }
	}
    else
    {
		// Normal host.
		url.host = urlString[0..iAny.index];
		urlString = urlString[iAny.index..$];
        debug(debug_pham_utl_utl_html) debug writeln("after.host=", urlString);
	}

	if (urlString[0] == ':')
    {
		auto jAny = urlString.simpleIndexOfAny("/?", 1);
        const end = jAny.found ? jAny.index : urlString.length;
        url.port = urlString[1..end];
		urlString = urlString[end..$];
        debug(debug_pham_utl_utl_html) debug writeln("after.port=", urlString);
		if (urlString.length == 0)
			return true;
	}

    iAny = urlString.simpleIndexOfAny("?#");
    if (!iAny.found)
    {
        url.path = urlString;
        return true;
    }

    url.path = urlString[0..iAny.index];
    const c = urlString[iAny.index];
    urlString = urlString[iAny.index+1..$];
    debug(debug_pham_utl_utl_html) debug writeln("after.path=", urlString);
    if (c == '?')
    {
        string paramString;
        const j = urlString.simpleIndexOf('#');
        if (j < 0)
        {
            paramString = urlString;
            urlString = null;
        }
        else
        {
            paramString = urlString[0..j];
            urlString = urlString[j+1..$];
        }
        debug(debug_pham_utl_utl_html) debug writeln("after.param=", urlString);
        url.params = uriSplitParameters(paramString);
    }

    url.fragment = urlString;
    return true;
}

pragma(inline, true)
bool sameName(scope const(char)[] name1, scope const(char)[] name2) pure
{
    return sicmp(name1, name2) == 0;
}

pragma(inline, true)
string uriDecode(scope const(char)[] str) pure
{
    import std.uri : decodeComponent;

    return decodeComponent(str);
}

enum URIMask : ubyte
{
    alpha = 0x01,
    digit = 0x02,
    marked = 0x04,
    reserved = 0x08,
    hash = 0x10, // '#'
}

enum uint uriEncodeUnescapedSet = URIMask.alpha | URIMask.digit | URIMask.marked;
immutable uriMarkedChars = "-_.!~*'()";
immutable uriReservedChars = "%;/?:@&=+$,";

// indexed by character
immutable ubyte[128] uriFlags = (
{
    ubyte[128] result;

    result['#'] |= URIMask.hash;

    foreach (c; 'A'..'Z' + 1)
    {
        result[c] |= URIMask.alpha;
        result[c + 0x20] |= URIMask.alpha; // lowercase letters
    }

    foreach (c; '0'..'9' + 1)
        result[c] |= URIMask.digit;

    foreach (c; uriReservedChars)
        result[c] |= URIMask.reserved;

    foreach (c; uriMarkedChars)
        result[c] |= URIMask.marked;

    return result;
})();

string uriEncode(string str) nothrow pure
{
    import std.algorithm.comparison : min;
    import pham.utl.utl_utf8 : nextUTF8Char;

    if (str.length == 0)
        return null;

    // Loop through to see encoding needed
    dchar c;
    size_t p;
    while (p < str.length)
    {
        const p2 = p;
        if (!nextUTF8Char(str, p, c))
            c = replacementUtf8Char;

        if (c < uriFlags.length && uriFlags[c] & uriEncodeUnescapedSet)
        {}
        else
        {
            p = p2;
            break;
        }
    }
    if (p >= str.length)
        return str;

    // There is character needs to be encoded
    auto result = Appender!string(str.length + min(str.length / 4, 500));
    result.put(str[0..p]);
    return result.uriEncode(str[p..$]).data;
}

ref Output uriEncode(Output)(return ref Output output, scope const(char)[] str) nothrow pure
{
    import std.ascii : hexDigits;
    import pham.utl.utl_utf8 : encodeUTF8MaxLength, encodeUTF8, nextUTF8Char;

    char[encodeUTF8MaxLength] buffer;
    dchar c;
    size_t p;

    while (p < str.length)
    {
        if (!nextUTF8Char(str, p, c))
            c = replacementUtf8Char;

        if (c < uriFlags.length && uriFlags[c] & uriEncodeUnescapedSet)
        {
            output.put(cast(char)c);
        }
        else
        {
            const eBuffer = encodeUTF8(buffer, c);
            foreach (e; eBuffer)
            {
                output.put('%');
                output.put(hexDigits[e >> 4]);
                output.put(hexDigits[e & 15]);
            }
        }
    }

    return output;
}

string uriParameters(scope const(NamedValue!string)[] elements) nothrow pure
{
    if (elements.length == 0)
        return null;

    size_t capacity;
    foreach (i, ref element; elements)
    {
        capacity += (i != 0); // separator
        capacity += element.name.length + 1 + element.value.length; // name + separator + value
    }

    auto result = Appender!string(capacity);
    return result.uriParameters(elements).data;
}

ref Output uriParameters(Output)(return ref Output output, scope const(NamedValue!string)[] elements) nothrow pure
{
    foreach (i, ref element; elements)
    {
        if (i)
            output.put('&');

        output.put(uriEncode(element.name));
        output.put('=');
        output.put(uriEncode(element.value));
    }
    return output;
}

NamedValue!string[] uriSplitParameters(string str) nothrow pure
{
    import pham.utl.utl_text : simpleCount, simpleSplitter;

    if (str.length == 0)
        return null;

    auto elements = str.simpleSplitter('&');
    NamedValue!string[] result;
    result.reserve(str.simpleCount('&') + 1);
    foreach (element; elements)
    {
        if (element.length == 0)
            continue;

        auto nameValue = element.simpleSplitter('=');
        result ~= nameValue.pair();
    }
    return result;
}

unittest // htmlEncode
{
    import std.ascii : fullHexDigits, letters;

    foreach (c; fullHexDigits)
    {
        assert(htmlEncode(c) == HtmlEncodeChar.none);
    }

    foreach (c; letters)
    {
        assert(htmlEncode(c) == HtmlEncodeChar.none);
    }

    foreach (c; "\t\v\r\n\f")
    {
        assert(htmlEncode(c) == HtmlEncodeChar.ctrl);
    }

    assert(htmlEncode('&') == HtmlEncodeChar.amp);
    assert(htmlEncode('<') == HtmlEncodeChar.lt);
    assert(htmlEncode('>') == HtmlEncodeChar.gt);
    assert(htmlEncode('"') == HtmlEncodeChar.dquot);
    assert(htmlEncode('\'') == HtmlEncodeChar.squot);
}

unittest // htmlEncode
{
    // No change
    auto s = htmlEncode("abc xyz");
    assert(s == "abc xyz", s);

    s = htmlEncode("");
    assert(s == "", s);

    // Changes
    s = htmlEncode("a& b<>c \"D' \x0Dz");
    assert(s == "a&amp; b&lt;&gt;c &quot;D&apos; &#13;z", s);
}

unittest // sameName
{
    assert(sameName("code", "Code"));
    assert(sameName("Error", "ERROR"));
    assert(sameName("error description", "Error DESCRIPTION"));
}

unittest // uriEncode
{
    import std.ascii : digits, letters;

    auto s = "foo bar".uriEncode();
    assert(s == "foo%20bar", s);

    s = "<>.™".uriEncode();
    assert(s == "%3C%3E.%E2%84%A2", s);

    s = "foo#a1-b2".uriEncode();
    assert(s == "foo%23a1-b2", s);

    s = "dlang-rocks!".uriEncode();
    assert(s == "dlang-rocks!", s);

    s = digits.uriEncode();
    assert(s == digits, s);

    s = letters.uriEncode();
    assert(s == letters, s);

    s = uriMarkedChars.uriEncode();
    assert(s == uriMarkedChars, s);

    s = uriReservedChars.uriEncode();
    assert(s == "%25%3B%2F%3F%3A%40%26%3D%2B%24%2C", s);
}

unittest // uriParameters
{
    alias NV = NamedValue!string;
    auto s = uriParameters([NV("abc", "123")]);
    assert(s == "abc=123", s);

    s = uriParameters([NV("abc", "123"), NV("XYZ", "45678")]);
    assert(s == "abc=123&XYZ=45678", s);
}

unittest // uriSplitParameters
{
    auto values = uriSplitParameters("");
    assert(values.length == 0);

    values = uriSplitParameters("abc=123");
    assert(values.length == 1);
    assert(values[0].name == "abc", values[0].name);
    assert(values[0].value == "123", values[0].value);

    values = uriSplitParameters("abc=123&XYZ=45678");
    assert(values.length == 2);
    assert(values[0].name == "abc", values[0].name);
    assert(values[0].value == "123", values[0].value);
    assert(values[1].name == "XYZ", values[1].name);
    assert(values[1].value == "45678", values[1].value);
}

unittest // parseURL
{
    alias Pair = NamedValue!string;
    URL url;
    bool parsed;

    parsed = url.parseURL("//foo/bar");
    assert(parsed);
    assert(url.scheme.length == 0, url.scheme);
    assert(url.user.length == 0, url.user);
    assert(url.password.length == 0, url.password);
	assert(url.host == "foo", url.host);
    assert(url.port.length == 0, url.port);
	assert(url.path == "/bar", url.path);
    assert(url.params.length == 0);
    assert(url.fragment.length == 0, url.fragment);

    parsed = url.parseURL("file:///foo/bar");
    assert(parsed);
    assert(url.scheme == "file", url.scheme);
    assert(url.user.length == 0, url.user);
    assert(url.password.length == 0, url.password);
    assert(url.host.length == 0, url.host);
    assert(url.port.length == 0, url.port);
    assert(url.path == "/foo/bar", url.path);
    assert(url.params.length == 0);
    assert(url.fragment.length == 0, url.fragment);

    // ipv6 hostnames!
	parsed = url.parseURL("https://bob:secret@[::1]:2771/foo/bar");
    assert(parsed);
	assert(url.scheme == "https", url.scheme);
	assert(url.user == "bob", url.user);
	assert(url.password == "secret", url.password);
	assert(url.host == "[::1]", url.host);
	assert(url.port == "2771", url.port);
	assert(url.path == "/foo/bar", url.path);
    assert(url.params.length == 0);
    assert(url.fragment.length == 0, url.fragment);

	// minimal
	parsed = url.parseURL("[::1]");
    assert(parsed);
    assert(url.scheme.length == 0, url.scheme);
    assert(url.user.length == 0, url.user);
    assert(url.password.length == 0, url.password);
	assert(url.host == "[::1]", url.host);
    assert(url.port.length == 0, url.port);
	assert(url.path.length == 0, url.path);
    assert(url.params.length == 0);
    assert(url.fragment.length == 0, url.fragment);

	parsed = url.parseURL("http://[::1]/foo");
    assert(parsed);
	assert(url.scheme == "http", url.scheme);
    assert(url.user.length == 0, url.user);
    assert(url.password.length == 0, url.password);
	assert(url.host == "[::1]", url.host);
    assert(url.port.length == 0, url.port);
	assert(url.path == "/foo", url.path);
    assert(url.params.length == 0);
    assert(url.fragment.length == 0, url.fragment);

	parsed = url.parseURL("https://[2001:0db8:0:0:0:0:1428:57ab]:123/?login=true#justkidding");
    assert(parsed);
	assert(url.scheme == "https");
    assert(url.user.length == 0, url.user);
    assert(url.password.length == 0, url.password);
	assert(url.host == "[2001:0db8:0:0:0:0:1428:57ab]");
    assert(url.port == "123", url.port);
	assert(url.path == "/");
    assert(url.params.length == 1);
    assert(url.params[0] == Pair("login", "true"));
	assert(url.fragment == "justkidding");

	parsed = url.parseURL("localhost:5984");
    assert(parsed);
    assert(url.scheme.length == 0, url.scheme);
    assert(url.user.length == 0, url.user);
    assert(url.password.length == 0, url.password);
	assert(url.host == "localhost", url.host);
    assert(url.port == "5984", url.port);
	assert(url.path.length == 0, url.path);
    assert(url.params.length == 0);
    assert(url.fragment.length == 0, url.fragment);


    parsed = url.parseURL("http://%23:%21%3A@example.org/%7B?%3B&%26=%3D#%23hash");
    assert(parsed);
    assert(url.scheme == "http", url.scheme);
	assert(url.user == "%23", url.user);
	assert(url.password == "%21%3A", url.password);
	assert(url.host == "example.org", url.host);
    assert(url.port.length == 0, url.port);
	assert(url.path == "/%7B", url.path);
    assert(url.params.length == 2);
	assert(url.params[0] == Pair("%3B", ""));
	assert(url.params[1] == Pair("%26", "%3D"));
	assert(url.fragment == "%23hash", url.fragment);

	parsed = url.parseURL("http://[::1]?foo=f1&foo2=f2");
    assert(parsed);
	assert(url.scheme == "http", url.scheme);
    assert(url.user.length == 0, url.user);
    assert(url.password.length == 0, url.password);
	assert(url.host == "[::1]", url.host);
    assert(url.port.length == 0, url.port);
	assert(url.path.length == 0, url.path);
    assert(url.params.length == 2);
	assert(url.params[0] == Pair("foo", "f1"));
	assert(url.params[1] == Pair("foo2", "f2"));
    assert(url.fragment.length == 0, url.fragment);

	parsed = url.parseURL("http://localhost.com?foo=f1&foo2=f2#hash");
    assert(parsed);
	assert(url.scheme == "http", url.scheme);
    assert(url.user.length == 0, url.user);
    assert(url.password.length == 0, url.password);
	assert(url.host == "localhost.com", url.host);
    assert(url.port.length == 0, url.port);
	assert(url.path.length == 0, url.path);
    assert(url.params.length == 2);
	assert(url.params[0] == Pair("foo", "f1"));
	assert(url.params[1] == Pair("foo2", "f2"));
    assert(url.fragment == "hash", url.fragment);
}

unittest // authIssuerFromWellKnownUri
{
    /* https://{host}{/path}/.well-known/oauth-authorization-server */

    auto r = authIssuerFromWellKnownUri("https://localhost.com/.well-known/oauth-authorization-server");
    assert(r.isOK, r.errorMessage);
    assert(r.value == "https://localhost.com", r.value);

    r = authIssuerFromWellKnownUri("https://localhost.com/.well-known/openid-configuration");
    assert(r.isOK, r.errorMessage);
    assert(r.value == "https://localhost.com", r.value);

    r = authIssuerFromWellKnownUri("https://localhost.com/p1/p2/.well-known/oauth-authorization-server");
    assert(r.isOK, r.errorMessage);
    assert(r.value == "https://localhost.com/p1/p2", r.value);

    r = authIssuerFromWellKnownUri("https://localhost.com/p1/p2/.well-known/openid-configuration");
    assert(r.isOK, r.errorMessage);
    assert(r.value == "https://localhost.com/p1/p2", r.value);

    r = authIssuerFromWellKnownUri("https://localhost.com/.well-known/oauth-authorization-server/p1/p2");
    assert(r.isOK, r.errorMessage);
    assert(r.value == "https://localhost.com/p1/p2", r.value);

    r = authIssuerFromWellKnownUri("https://localhost.com/.well-known/openid-configuration/p1/p2");
    assert(r.isOK, r.errorMessage);
    assert(r.value == "https://localhost.com/p1/p2", r.value);

    // Error if mix path placement
    r = authIssuerFromWellKnownUri("https://localhost.com/a/.well-known/oauth-authorization-server/b");
    assert(r.isError, r.errorMessage);

    r = authIssuerFromWellKnownUri("https://localhost.com/a/.well-known/openid-configuration/b");
    assert(r.isError, r.errorMessage);

    // Error if no scheme
    r = authIssuerFromWellKnownUri("//localhost.com/.well-known/oauth-authorization-server");
    assert(r.isError, r.errorMessage);

    r = authIssuerFromWellKnownUri("//localhost.com/.well-known/openid-configuration");
    assert(r.isError, r.errorMessage);

    // Error if no wellknown
    r = authIssuerFromWellKnownUri("//localhost.com/.well-known/b");
    assert(r.isError, r.errorMessage);

    r = authIssuerFromWellKnownUri("//localhost.com/oauth-authorization-server/b");
    assert(r.isError, r.errorMessage);

    r = authIssuerFromWellKnownUri("//localhost.com/openid-configuration/b");
    assert(r.isError, r.errorMessage);

    r = authIssuerFromWellKnownUri("//localhost.com/well-known/oauth-authorization-server/b");
    assert(r.isError, r.errorMessage);

    r = authIssuerFromWellKnownUri("//localhost.com/well-known/openid-configuration/b");
    assert(r.isError, r.errorMessage);
}
