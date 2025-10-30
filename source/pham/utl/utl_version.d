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

module pham.utl.utl_version;

import std.array : join, split;
import std.algorithm.comparison : min;
import std.algorithm.iteration : map;
import std.conv : to;
import std.string : strip;
import pham.utl.utl_array_static : ShortStringBuffer;
import pham.utl.utl_numeric_parser : NumericParsedKind, parseIntegral;
import pham.utl.utl_result : cmp;

struct VersionString
{
nothrow @safe:

public:
    enum maxPartLength = 4;
    enum stopPartValue = uint.max; // A way to signal logical order stopped on certain version index/position part

    static struct Parti
    {
    nothrow @safe:

    public:
        this(scope const(uint)[] parti) @nogc pure
        {
            const len = min(parti.length, maxPartLength);
            this._length = cast(ubyte)len;
            this.data[0..len] = parti[0..len];
        }

        this(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) @nogc pure
        {
            this._length = 4;
            this.data[0] = major;
            this.data[1] = minor;
            this.data[2] = release;
            this.data[3] = build;
        }

        this(const(uint) major, const(uint) minor) @nogc pure
        {
            this._length = 2;
            this.data[0] = major;
            this.data[1] = minor;
        }

        int opCmp(scope const(Parti) rhs) const @nogc pure
        {
            const stopLHS = this.stopLength;
            const stopRHS = rhs.stopLength;
            const stopLen = stopRHS > stopLHS ? stopLHS : stopRHS;

            const cmpLHS = this._length > stopLen ? stopLen : this._length;
            const cmpRHS = rhs._length > stopLen ? stopLen : rhs._length;
            const cmpLen = cmpRHS > cmpLHS ? cmpLHS : cmpRHS;

            foreach (i; 0..cmpLen)
            {
                const result = cmp(this.data[i], rhs.data[i]);
                if (result != 0)
                    return result;
            }

            return cmp(cmpLHS, cmpRHS);
        }

        bool opEquals(scope const(Parti) rhs) const @nogc pure
        {
            return opCmp(rhs) == 0;
        }

        size_t stopLength() const @nogc pure
        {
            foreach (i; 0..maxPartLength)
            {
                if (data[i] == stopPartValue)
                    return i;
            }
            return maxPartLength;
        }

        string toString() const pure
        {
            return _length ? data[0.._length].map!(v => v.to!string()).join(".") : null;
        }

        @property bool empty() const @nogc pure
        {
            return _length == 0;
        }

        @property size_t length() const @nogc pure
        {
            return _length;
        }

        @property size_t length(const(size_t) newLength) @nogc pure
        {
            _length = cast(ubyte)min(newLength, maxPartLength);
            return _length;
        }

    public:
        uint[maxPartLength] data;

    private:
        ubyte _length;
    }

    static struct Parts
    {
        import pham.utl.utl_convert : putNumber;

    nothrow @safe:

    public:
        this(scope const(uint)[] parti) pure
        {
            const len = min(parti.length, maxPartLength);
            ShortStringBuffer!char tempBuffer;
            this._length = cast(ubyte)len;
            foreach (i; 0..len)
                this.data[i] = putNumber(tempBuffer.clear(), parti[i]).toString();
        }

        bool opEquals(scope const(Parts) rhs) const @nogc pure
        {
            const sameLength = this._length == rhs._length;
            if (sameLength)
            {
                foreach (i; 0..this._length)
                {
                    if (this.data[i] != rhs.data[i])
                        return false;
                }
            }
            return sameLength;
        }

        static Parts parse(string versionString) pure
        {
            static immutable uint[] n = [];
            return versionString.length != 0 ? Parts(split(versionString, ".")) : Parts(n);
        }

        /**
         * Convert version part strings into their integral presentation.
         * If a string is not able to be converted because of empty or invalid character(s),
         * the value will be substituted with zero
         */
        Parti toParti() const @nogc pure scope
        {
            Parti result;
            result._length = _length;
            foreach (i; 0.._length)
            {
                if (parseIntegral(data[i], result.data[i]) != NumericParsedKind.ok)
                    result.data[i] = 0;
            }
            return result;
        }

        string toString() const pure
        {
            return _length ? data[0.._length].join(".") : null;
        }

        @property bool empty() const @nogc pure
        {
            return _length == 0;
        }

        @property size_t length() const @nogc pure
        {
            return _length;
        }

        @property size_t length(const(size_t) newLength) @nogc pure
        {
            _length = cast(ubyte)min(newLength, maxPartLength);
            return _length;
        }

    public:
        string[maxPartLength] data;

    private:
        this(string[] parts) pure
        {
            const len = min(parts.length, maxPartLength);
            this._length = cast(ubyte)len;
            foreach (i; 0..len)
                this.data[i] = parts[i].strip();
        }

    private:
        ubyte _length;
    }

public:
    this(string versionString) pure
    {
        this.parts = Parts.parse(versionString);
    }

    this(scope const(uint)[] parti) pure
    {
        this.parts = Parts(parti);
    }

    this(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) pure
    {
        this([major, minor, release, build]);
    }

    this(const(uint) major, const(uint) minor) pure
    {
        this([major, minor]);
    }

    int opCmp(scope const(VersionString) rhs) const @nogc pure
    {
        return opCmp(rhs.parts.toParti());
    }

    int opCmp(string rhs) const pure
    {
        auto rhsVersion = VersionString(rhs);
        return opCmp(rhsVersion.parts.toParti());
    }

    int opCmp(scope const(uint)[] rhs) const @nogc pure
    {
        return opCmp(Parti(rhs));
    }

    int opCmp(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) const @nogc pure
    {
        return opCmp(Parti(major, minor, release, build));
    }

    int opCmp(const(uint) major, const(uint) minor) const @nogc pure
    {
        return opCmp(Parti(major, minor));
    }

    int opCmp(scope const(Parti) rhs) const @nogc pure
    {
        return parts.toParti().opCmp(rhs);
    }

    bool opEquals(scope const(VersionString) rhs) const @nogc pure
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(string rhs) const pure
    {
        return opCmp(rhs) == 0;
    }

    bool opEquals(scope const(uint)[] rhs) const @nogc pure
    {
        return opCmp(Parti(rhs)) == 0;
    }

    bool opEquals(const(uint) major, const(uint) minor, const(uint) release, const(uint) build) const @nogc pure
    {
        return opCmp(Parti(major, minor, release, build)) == 0;
    }

    bool opEquals(const(uint) major, const(uint) minor) const @nogc pure
    {
        return opCmp(Parti(major, minor)) == 0;
    }

    string toString() const pure
    {
        return parts.toString();
    }

    @property bool empty() const @nogc pure
    {
        return parts.empty;
    }

public:
    Parts parts;
}


nothrow @safe unittest // VersionString
{
    import std.conv : to;

    const v1Str = "2.2.3.4";
    const v1 = VersionString(v1Str);
    assert(v1.parts.data[0] == "2");
    assert(v1.parts.data[1] == "2");
    assert(v1.parts.data[2] == "3");
    assert(v1.parts.data[3] == "4");
    assert(v1.toString() == v1Str);
    assert(v1 == VersionString(v1Str));
    assert(v1 == v1Str);

    const v2Str = "2.2.0.0";
    const v2 = VersionString(v2Str);
    assert(v2.parts.data[0] == "2");
    assert(v2.parts.data[1] == "2");
    assert(v2.parts.data[2] == "0");
    assert(v2.parts.data[3] == "0");
    assert(v2.toString() == v2Str);
    assert(v2 == v2Str);
    assert(v2 == VersionString(v2Str));

    assert(v1 > v2);

    const v3 = VersionString(2, VersionString.stopPartValue, 2, 0);
    assert(v3.parts.data[0] == "2");
    assert(v3.parts.data[1] == VersionString.stopPartValue.to!string());
    assert(v3.parts.data[2] == "2");
    assert(v3.parts.data[3] == "0");
    assert(v1 == v3);
    assert(v2 == v3);

    const v4Str = "4.4.4.4";
    const v4 = VersionString(v4Str);
    assert(v4.parts.data[0] == "4");
    assert(v4.parts.data[1] == "4");
    assert(v4.parts.data[2] == "4");
    assert(v4.parts.data[3] == "4");
    assert(v3 < v4);

    const vbStr = "1.2";
    const vb = VersionString(vbStr);
    assert(vb.parts.data[0] == "1");
    assert(vb.parts.data[1] == "2");
    assert(vb.parts.data[2].length == 0);
    assert(vb.parts.data[3].length == 0);
    assert(vb.toString() == vbStr);

    auto vNull = VersionString("");
    assert(vNull.toString() == "");
    assert(vNull < "1.2.3.4");
    assert("1.2.3.4" > vNull);
}
