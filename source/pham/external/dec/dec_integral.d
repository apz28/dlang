module pham.external.dec.dec_integral;

import core.bitop : bsf, bsr;
import core.checkedint: adds, addu, mulu, subs, subu;
import std.bitmanip : bigEndianToNative, nativeToBigEndian;
import std.traits: CommonType, isSigned, isSomeChar, isUnsigned, Signed, Unqual, Unsigned;

nothrow @safe:
package(pham.external.dec):

/* ****************************************************************************************************************** */
/* n BIT UNSIGNED IMPLEMENTATION                                                                                    */
/* ****************************************************************************************************************** */

template isCustomUnsignedBit(T)
{
    alias UT = Unqual!T;
    enum isCustomUnsignedBit = is(UT: UnsignedBit!Bytes, int Bytes);
}

template isAnyUnsignedBit(T)
{
    alias UT = Unqual!T;
    enum isAnyUnsignedBit = isUnsigned!UT || isCustomUnsignedBit!UT;
}

template isUnsignedAssignableBit(T, U)
{
    enum isUnsignedAssignableBit = T.sizeof >= U.sizeof && isAnyUnsignedBit!T && isAnyUnsignedBit!U;
}

bool isHexString(scope const(char)[] s) @nogc pure
{
    return s.length >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X');
}

inout(T)[] chopLeadingZero(T)(inout(T)[] a) @nogc nothrow pure @safe
{
    if (a.length <= 1)
        return a;
        
    static if (isSomeChar!T)
        enum zero = '0';
    else
        enum zero = 0;
        
    size_t i;
    while (i < a.length && a[i] == zero)
        i++;
    return i == a.length ? a[$-1..$] : a[i..$];
}

unittest // chopLeadingZero
{
    ubyte[] e;
    assert(chopLeadingZero(e).length == 0);
    assert(chopLeadingZero([0]) == [0]);
    assert(chopLeadingZero([0,1,2,3]) == [1,2,3]);
    assert(chopLeadingZero([1,2]) == [1,2]);
}

inout(T)[] chopRightSlice(T)(ref inout(T)[] a, size_t count) @nogc nothrow pure @safe
{
    const all = a.length <= count;
    auto result = all ? a : a[$-count..$];
    a = all ? null : a[0..$-count];
    return result;
}

unittest // chopRightSlice
{
    string a, r;
    
    a = "";
    r = chopRightSlice(a, 2);
    assert(r.length == 0);
    assert(a.length == 0);
    
    a = "sOmEsTrInG";
    r = chopRightSlice(a, 2);
    assert(r == "nG");
    assert(a == "sOmEsTrI");    
    r = chopRightSlice(a, 100);
    assert(r == "sOmEsTrI");
    assert(a.length == 0);
}

struct UnsignedBit(int Bytes)
if (Bytes >= 16 && (Bytes & (Bytes - 1)) == 0)
{
@nogc nothrow @safe:

    enum HALFSize = Bytes / 2;
    alias HALF = makeUnsignedBit!HALFSize;
    alias THIS = typeof(this);

    version(LittleEndian)
    {
        HALF lo;
        HALF hi;
    }
    else
    {
        HALF hi;
        HALF lo;
    }

    enum min = THIS();
    enum max = THIS(HALF.max, HALF.max);

    this(T, U)(auto const ref T hi, auto const ref U lo) pure
    if (isUnsignedAssignableBit!(HALF, T) && isUnsignedAssignableBit!(HALF, U))
    {
        this.hi = hi;
        this.lo = lo;
    }

    this(T)(auto const ref T x) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        this.lo = x;
    }

    this(scope const(ubyte)[] bigEndianBytes) pure
    in
    {
        assert(bigEndianBytes.length <= Bytes);
    }
    do
    {
        static if (Bytes <= 16)
        {
            lo = fromBigEndianBytes!HALF(chopRightSlice(bigEndianBytes, HALFSize));
            hi = fromBigEndianBytes!HALF(chopRightSlice(bigEndianBytes, HALFSize));
        }
        else
        {
            lo = HALF(chopRightSlice(bigEndianBytes, HALFSize));
            hi = HALF(chopRightSlice(bigEndianBytes, HALFSize));
        }
    }

    this(const(char)[] s) pure // TODO scope
    in
    {
        assert(s.length, "Empty string");
        assert(!isHexString(s) || s.length > 2, "Empty hexadecimal string");
    }
    do
    {
        size_t i = 0;
        if (isHexString(s))
        {
            i += 2;
            while (i < s.length && (s[i] == '0' || s[i] == '_'))
                ++i;
            int width = 0;
            enum maxWidth = THIS.sizeof * 8;
            while (i < s.length)
            {
                assert(width < maxWidth, s); //"Overflow"
                const char c = s[i++];
                if (c >= '0' && c <= '9')
                {
                    this <<= 4;
                    lo |= cast(uint)(c - '0');
                    width += 4;
                }
                else if (c >= 'A' && c <= 'F')
                {
                    this <<= 4;
                    lo |= cast(uint)(c - 'A' + 10);
                    width += 4;
                }
                else if (c >= 'a' && c <= 'f')
                {
                    this <<= 4;
                    lo |= cast(uint)(c - 'a' + 10);
                    width += 4;
                }
                else
                    assert(c == '_', s); //"Invalid character in input string"
            }
        }
        else
        {
            while (i < s.length)
            {
                const char c = s[i++];
                if (c >= '0' && c <= '9')
                {
                    bool overflow;
                    auto r = fma(this, 10U, cast(uint)(c - '0'), overflow);
                    assert(!overflow, s); //Overflow
                    this = r;
                }
                else
                    assert(c == '_', s); //"Invalid character in input string"
            }
        }
    }

    auto ref opAssign(T)(auto const ref T x) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        this.lo = x;
        this.hi = 0U;
        return this;
    }

    auto opUnary(string op : "+")() const pure
    {
        return this;
    }

    auto opUnary(string op : "-")() const pure
    {
        return ++(~this);
    }

    auto opUnary(string op : "~")() const pure
    {
        return THIS(~hi, ~lo);
    }

    auto ref opUnary(string op :"++")() pure
    {
        ++lo;
        if (!lo)
            ++hi;
        return this;
    }

    auto ref opUnary(string op :"--")() pure
    {
        --lo;
        if (lo == HALF.max)
            --hi;
        return this;
    }

    bool opEquals(T)(const(T) value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        return hi == 0U && lo == value;
    }

    bool opEquals(T : THIS)(auto const ref T value) const pure
    {
        return hi == value.hi && lo == value.lo;
    }

    int opCmp(T)(const(T) value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        if (hi)
            return 1;
        else if (lo > value)
            return 1;
        else if (lo < value)
            return -1;
        else
            return 0;
    }

    int opCmp(T: THIS)(auto const ref T value) const pure
    {
        if (hi > value.hi)
            return 1;
        else if (hi < value.hi)
            return -1;
        else if (lo > value.lo)
            return 1;
        else if (lo < value.lo)
            return -1;
        else
            return 0;
    }

    auto opBinary(string op : "|", T : THIS)(auto const ref T value) const pure
    {
        return THIS(this.hi | value.hi, this.lo | value.lo);
    }

    auto opBinary(string op: "|", T)(auto const ref T value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        return THIS(this.hi, this.lo | value);
    }

    auto ref opOpAssign(string op : "|", T : THIS)(auto const ref T value) pure
    {
        this.hi |= value.hi;
        this.lo |= value.lo;
        return this;
    }

    auto ref opOpAssign(string op : "|", T)(auto const ref T value) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        this.lo |= value;
        return this;
    }

    auto opBinary(string op : "&", T : THIS)(auto const ref T value) const pure
    {
        return THIS(this.hi & value.hi, this.lo & value.lo);
    }

    auto opBinary(string op : "&", T)(auto const ref T value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        return THIS(0U, this.lo & value);
    }

    auto ref opOpAssign(string op : "&", T: THIS)(auto const ref T value) pure
    {
        this.hi &= value.hi;
        this.lo &= value.lo;
        return this;
    }

    auto ref opOpAssign(string op : "&", T)(auto const ref T value) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        this.hi = 0U;
        this.lo &= value;
        return this;
    }

    auto opBinary(string op : "^", T : THIS)(auto const ref T value) const pure
    {
        return THIS(this.hi ^ value.hi, this.lo ^ value.lo);
    }

    auto opBinary(string op : "^", T)(auto const ref T value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        return THIS(this.hi ^ 0UL, this.lo ^ value);
    }

    auto ref opOpAssign(string op : "^", T : THIS)(auto const ref T value) pure
    {
        this.hi ^= value.hi;
        this.lo ^= value.lo;
        return this;
    }

    auto ref opOpAssign(string op : "^", T)(auto const ref T value) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        this.hi ^= 0U;
        this.lo ^= value;
        return this;
    }

    auto opBinary(string op)(const(int) shift) const pure
    if (op == ">>" || op == ">>>")
    in
    {
        assert(shift >= 0 && shift < THIS.sizeof * 8);
    }
    do
    {
        enum int halfBits = HALF.sizeof * 8;
        THIS ret = void;

        if (shift == halfBits)
        {
            ret.lo = this.hi;
            ret.hi = 0U;
        }
        else if (shift > halfBits)
        {
            ret.lo = this.hi >>> (shift - halfBits);
            ret.hi = 0U;
        }
        else if (shift != 0)
        {
            ret.lo = (this.hi << (halfBits - shift)) | (this.lo >>> shift);
            ret.hi = this.hi >>> shift;
        }
        else
            ret = this;
        return ret;
    }

    auto ref opOpAssign(string op)(const(int) shift) pure
    if (op == ">>" || op == ">>>")
    in
    {
        assert(shift >= 0 && shift < THIS.sizeof * 8);
    }
    do
    {
        enum int halfBits = HALF.sizeof * 8;
        if (shift == halfBits)
        {
            lo = hi;
            hi = 0U;
        }
        else if (shift > halfBits)
        {
            lo = hi >>> (shift - halfBits);
            hi = 0U;
        }
        else if (shift != 0)
        {
            lo = (hi << (halfBits - shift)) | (lo >>> shift);
            hi >>>= shift;
        }
        return this;
    }

    auto opBinary(string op)(const(int) shift) const pure
    if (op == "<<")
    in
    {
        assert(shift >= 0 && shift < THIS.sizeof * 8);
    }
    do
    {
        THIS ret = void;
        enum int halfBits = HALF.sizeof * 8;

        if (shift == halfBits)
        {
            ret.hi = this.lo;
            ret.lo = 0U;
        }
        else if (shift > halfBits)
        {
            ret.hi = this.lo << (shift - halfBits);
            ret.lo = 0U;
        }
        else if (shift != 0)
        {
            ret.hi = (this.lo >>> (halfBits - shift)) | (this.hi << shift);
            ret.lo = this.lo << shift;
        }
        else
            ret = this;
        return ret;
    }

    auto ref opOpAssign(string op)(const(int) shift) pure
    if (op == "<<")
    in
    {
        assert(shift >= 0 && shift < THIS.sizeof * 8);
    }
    do
    {
        enum int halfBits = HALF.sizeof * 8;

        if (shift == halfBits)
        {
            hi = lo;
            lo = 0U;
        }
        else if (shift > halfBits)
        {
            hi = lo << (shift - halfBits);
            lo = 0U;
        }
        else if (shift != 0)
        {
            hi = (lo >>> (halfBits - shift)) | (hi << shift);
            lo <<= shift;
        }
        return this;
    }

    auto opBinary(string op : "+", T)(const(T) value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        THIS ret = this;
        ret.hi += xadd(ret.lo, value);
        return ret;
    }

    auto ref opOpAssign(string op : "+", T)(const(T) value) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        hi += xadd(lo, value);
        return this;
    }

    auto opBinary(string op : "+", T : THIS)(const(T) value) const pure
    {
        THIS ret = this;
        ret.hi += xadd(ret.lo, value.lo);
        ret.hi += value.hi;
        return ret;
    }

    auto ref opOpAssign(string op : "+", T : THIS)(auto const ref T value) pure
    {
        hi += xadd(this.lo, value.lo);
        hi += value.hi;
        return this;
    }

    auto opBinary(string op : "-", T)(const(T) value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        THIS ret = this;
        ret.hi -= xsub(ret.lo, value);
        return ret;
    }

    auto ref opOpAssign(string op : "-", T)(const(T) value) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        hi -= xsub(lo, value);
        return this;
    }

    auto opBinary(string op : "-", T : THIS)(const(T) value) const pure
    {
        THIS ret = this;
        ret.hi -= xsub(ret.lo, value.lo);
        ret.hi -= value.hi;
        return ret;
    }

    auto ref opOpAssign(string op : "-", T : THIS)(auto const ref T value) pure
    {
        this.hi -= xsub(this.lo, value.lo);
        this.hi -= value.hi;
        return this;
    }

    auto opBinary(string op : "*", T)(const(T) value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        THIS ret = xmul(this.lo, value);
        ret.hi += this.hi * value;
        return ret;
    }

    auto ref opOpAssign(string op : "*", T)(const(T) value) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        THIS ret = xmul(this.lo, value);
        ret.hi += this.hi * value;
        return this = ret;
    }

    auto opBinary(string op : "*", T : THIS)(const(T) value) const pure
    {
        auto ret = xmul(lo, value.lo);
        ret.hi += this.hi * value.lo + this.lo * value.hi;
        return ret;
    }

    auto ref opOpAssign(string op : "*", T : THIS)(const(T) value) pure
    {
        auto ret = xmul(lo, value.lo);
        ret.hi += this.hi * value.lo + this.lo * value.hi;
        return this = ret;
    }

    auto opBinary(string op : "/", T)(const(T) value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        THIS q = this;
        divrem(q, value);
        return q;
    }

    auto ref opOpAssign(string op :"/", T)(const(T) value) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        divrem(this, value);
        return this;
    }

    auto opBinary(string op : "/", T : THIS)(const(T) value) const pure
    {
        THIS q = this;
        divrem(q, value);
        return q;
    }

    auto ref opOpAssign(string op : "/", T : THIS)(const(T) value) pure
    {
        divrem(this, value);
        return this;
    }

    auto opBinary(string op : "%", T)(const(T) value) const pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        THIS q = this;
        return divrem(q, value);
    }

    auto ref opOpAssign(string op : "%", T)(const(T) value) pure
    if (isUnsignedAssignableBit!(HALF, T))
    {
        THIS q = this;
        return this = divrem(q, value);
    }

    auto opBinary(string op : "%", T : THIS)(const(T) value) const pure
    {
        THIS q = this;
        return divrem(q, value);
    }

    auto ref opOpAssign(string op : "%", T : THIS)(const(T) value) pure
    {
        THIS q = this;
        return this = divrem(q, value);
    }

    auto opCast(T)() const pure
    {
        static if (is(T : bool))
            return cast(T)(lo | hi);
        else static if (isSomeChar!T)
            return cast(T)lo;
        else static if (isUnsigned!T)
            return cast(T)lo;
        else static if (isUnsignedAssignableBit!(HALF, T))
            return cast(T)lo;
        else static if (is(T : THIS))
            return this;
        else
            static assert("Cannot cast '" ~ Unqual!THIS.stringof ~ "' to '" ~ Unqual!T.stringof ~ "'");
    }

    ubyte[] toBigEndianBytes(return ubyte[] bytes) const @nogc
    in
    {
        assert(bytes.length == Bytes);
    }
    do
    {
        static if (Bytes <= 16)
        {
            bytes[0..HALFSize] = nativeToBigEndian(hi);
            bytes[HALFSize..Bytes] = nativeToBigEndian(lo);
        }
        else
        {
            hi.toBigEndianBytes(bytes[0..HALFSize]);
            lo.toBigEndianBytes(bytes[HALFSize..Bytes]);
        }
        return chopLeadingZero(bytes);
    }
}

alias uint128 = UnsignedBit!16;
alias uint256 = UnsignedBit!32;
alias uint512 = UnsignedBit!64;

T fromBigEndianBytes(T)(scope const(ubyte)[] bigEndianBytes) @nogc nothrow pure @safe
if (isUnsigned!T)
{
    ubyte[T.sizeof] b = 0;
    size_t n = bigEndianBytes.length;
    if (n >= T.sizeof)
        b[0..T.sizeof] = bigEndianBytes[0..T.sizeof];
    else
    {
        size_t i = T.sizeof - 1;
        while (n--)
        {
            b[i--] = bigEndianBytes[n];
        }
    }
    return bigEndianToNative!T(b);
}

T fromBigEndianBytes(T)(scope const(ubyte)[] bigEndianBytes) @nogc nothrow pure @safe
if (isCustomUnsignedBit!T)
{
    return T(bigEndianBytes);
}

ubyte[] toBigEndianBytes(T)(T u, return ubyte[] bytes) @nogc pure
if (isUnsigned!T)
in
{
    assert(bytes.length == T.sizeof);
}
do
{
    bytes[0..T.sizeof] = nativeToBigEndian(u);
    return chopLeadingZero(bytes);
}

///Returns true if all specified types are UnsignedBit... types.
template isUnsignedBit(Ts...)
{
    enum isUnsignedBit =
    {
        bool result = Ts.length > 0;
        static foreach (t; Ts)
        {
            if (!(is(Unqual!t == uint128) || is(Unqual!t == uint256) || is(Unqual!t == uint512)))
                result = false;
        }
        return result;
    }();
}

template makeUnsignedBit(int Bytes)
{
    static if (Bytes >= 16)
        alias makeUnsignedBit = UnsignedBit!Bytes;
    else static if (Bytes == 8)
        alias makeUnsignedBit = ulong;
    else static if (Bytes == 4)
        alias makeUnsignedBit = uint;
    else static if (Bytes == 2)
        alias makeUnsignedBit = ushort;
    else static if (Bytes == 1)
        alias makeUnsignedBit = ubyte;
    else
        static assert(0, "Unsupport system for makeUnsignedBit");
}

T toUnsign(T)(const(char)[] s, ref bool overflow) @nogc nothrow pure @safe // TODO scope
if (T.sizeof >= 4 && isAnyUnsignedBit!T)
{
    alias UT = Unqual!T;

    static if (is(UT == uint) || is(UT == ulong))
    {
        UT result = 0;
        size_t i = 0;
        if (isHexString(s))
        {
            i += 2;
            while (i < s.length && (s[i] == '0' || s[i] == '_'))
                ++i;
            int width = 0;
            enum maxWidth = UT.sizeof * 8;
            while (i < s.length)
            {
                if (width >= maxWidth)
                {
                    overflow = true;
                    return result;
                }

                const char c = s[i++];
                if (c >= '0' && c <= '9')
                {
                    result = (result << 4) | cast(uint)(c - '0');
                    width += 4;
                }
                else if (c >= 'A' && c <= 'F')
                {
                    result = (result << 4) | cast(uint)(c - 'A' + 10);
                    width += 4;
                }
                else if (c >= 'a' && c <= 'f')
                {
                    result = (result << 4) | cast(uint)(c - 'a' + 10);
                    width += 4;
                }
                else
                    assert(c == '_', s); //"Invalid character in input string"
            }
        }
        else
        {
            while (i < s.length)
            {
                const char c = s[i++];
                if (c >= '0' && c <= '9')
                {
                    bool overflow1, overflow2;
                    result = addu(mulu(result, 10U, overflow1), cast(uint)(c - '0'), overflow2);
                    if (overflow1 || overflow2)
                    {
                        overflow = true;
                        return result;
                    }
                }
                else
                    assert(c == '_', s); //"Invalid character in input string";
            }
        }
        return result;
    }
    else
        return UT(s);
}

unittest
{
    import std.typetuple;
    import std.random;

    auto gen = Random();

    T rnd(T)()
    {
        scope (failure) assert(0, "Assume nothrow failed");

        static if (is(T == uint))
            return uniform(1U, uint.max, gen);
        else static if (is(T == ulong))
            return uniform(1UL, ulong.max, gen);
        else
            return T(rnd!(T.HALF)(), rnd!(T.HALF)());
    }

    foreach (T; TypeTuple!(UnsignedBit!16, UnsignedBit!32, UnsignedBit!64))
    {
        enum zero = T(0U);
        enum one = T(1U);
        enum two = T(2U);
        enum three = T(3U);
        enum big = T(0x3333333333U, 0x4444444444U);
        enum next = T(1U, 0U);
        enum previous = T(0U, T.HALF.max);

        assert(zero == zero);
        assert(zero <= zero);
        assert(zero >= zero);
        assert(zero < one);
        assert(zero < two);
        assert(zero < three);
        assert(zero < big);
        assert(zero < next);
        assert(zero < previous);

        assert(one > zero);
        assert(one >= zero);
        assert(one >= one);
        assert(one == one);
        assert(one < two);
        assert(one < three);
        assert(one < big);
        assert(one < next);
        assert(one < previous);

        assert(two > zero);
        assert(two >= zero);
        assert(two >= one);
        assert(two > one);
        assert(two == two);
        assert(two < three);
        assert(two < big);
        assert(two < next);
        assert(two < previous);

        assert(three > zero);
        assert(three >= zero);
        assert(three >= one);
        assert(three > one);
        assert(three >= two);
        assert(three == three);
        assert(three < big);
        assert(three < next);
        assert(three < previous);

        assert(big > zero);
        assert(big >= zero);
        assert(big >= one);
        assert(big > one);
        assert(big >= two);
        assert(big >= three);
        assert(big == big);
        assert(big > next);
        assert(big > previous);

        assert(next > zero);
        assert(next >= zero);
        assert(next >= one);
        assert(next > one);
        assert(next >= two);
        assert(next >= three);
        assert(next <= big);
        assert(next == next);
        assert(next > previous);

        assert(previous > zero);
        assert(previous >= zero);
        assert(previous >= one);
        assert(previous > one);
        assert(previous >= two);
        assert(previous >= three);
        assert(previous <= big);
        assert(previous <= next);
        assert(previous == previous);

        assert(zero == 0U);
        assert(zero <= 0U);
        assert(zero >= 0U);
        assert(zero < 1U);
        assert(zero < 2U);
        assert(zero < 3U);
        assert(zero < ulong.max);

        assert(one > 0U);
        assert(one >= 0U);
        assert(one >= 1U);
        assert(one == 1U);
        assert(one < 2U);
        assert(one < 3U);
        assert(one < ulong.max);

        assert(two > 0U);
        assert(two >= 0U);
        assert(two >= 1U);
        assert(two > 1U);
        assert(two == 2U);
        assert(two < 3U);
        assert(two < ulong.max);

        assert(three > 0U);
        assert(three >= 0U);
        assert(three >= 1U);
        assert(three > 1U);
        assert(three >= 2U);
        assert(three == 3U);
        assert(three < ulong.max);

        assert(big > 0U);
        assert(big >= 0U);
        assert(big >= 1U);
        assert(big > 1U);
        assert(big >= 2U);
        assert(big >= 3U);
        assert(big > ulong.max);

        assert(next > 0U);
        assert(next >= 0U);
        assert(next >= 1U);
        assert(next > 1U);
        assert(next >= 2U);
        assert(next >= 3U);
        assert(next > ulong.max);

        assert(previous > 0U);
        assert(previous >= 0U);
        assert(previous >= 1U);
        assert(previous > 1U);
        assert(previous >= 2U);
        assert(previous >= 3U);
        assert(previous == previous);

        assert(~~zero == zero);
        assert(~~one == one);
        assert(~~two == two);
        assert(~~three == three);
        assert(~~big == big);
        assert(~~previous == previous);
        assert(~~next == next);

        assert((one | one) == one);
        assert((one | zero) == one);
        assert((one & one) == one);
        assert((one & zero) == zero);
        assert((big & ~big) == zero);
        assert((one ^ one) == zero);
        assert((big ^ big) == zero);
        assert((one ^ zero) == one);

        assert(big >> 0 == big);
        assert(big << 0 == big);

        assert(big << 1 > big);
        assert(big >> 1 < big);

        auto x = big << 3;
        auto y = x >> 3;
        assert((big << 3) >> 3 == big);
        assert((one << 127) >> 127 == one);
        assert((one << 64) >> 64 == one);

        assert(zero + zero == zero);
        assert(zero + one == one);
        assert(zero + two == two);
        assert(zero + three == three);
        assert(zero + big == big);
        assert(zero + previous == previous);
        assert(zero + next == next);

        assert(one + zero == one);
        assert(one + one == two);
        assert(one + two == three);
        assert(one + three > three);
        assert(one + big > big);
        assert(one + previous == next);
        assert(one + next > next);

        assert(two + zero == two);
        assert(two + one == three);
        assert(two + two > three);
        assert(two + three > three);
        assert(two + big > big);
        assert(two + previous > next);
        assert(two + next > next);

        assert(three + zero == three);
        assert(three + one > three);
        assert(three + two > three);
        assert(three + three > three);
        assert(three + big > big);
        assert(three + previous > next);
        assert(three + next > next);

        assert(big + zero == big);
        assert(big + one > big);
        assert(big + two > big + one);
        assert(big + three > big + two);
        assert(big + big > big);
        assert(big + previous > next);
        assert(big + next > next);

        assert(previous + zero == previous);
        assert(previous + one == next);
        assert(previous + two > next);
        assert(previous + three == next + two);
        assert(previous + big > big);
        assert(previous + previous > previous);
        assert(previous + next > previous);

        assert(next + zero == next);
        assert(next + one > next);
        assert(next + two > next);
        assert(next + three >= next + two);
        assert(next + big > big);
        assert(next + previous > next);
        assert(next + next > next);

        assert(zero + 0U == zero);
        assert(zero + 1U == one);
        assert(zero + 2U == two);
        assert(zero + 3U == three);

        assert(one + 0U == one);
        assert(one + 1U == two);
        assert(one + 2U == three);
        assert(one + 3U > three);

        assert(two + 0U == two);
        assert(two + 1U == three);
        assert(two + 2U > three);
        assert(two + 3U > three);

        assert(three + 0U == three);
        assert(three + 1U > three);
        assert(three + 2U > three);
        assert(three + 3U > three);

        assert(big + 0U == big);
        assert(big + 1U > big);
        assert(big + 2U > big + 1U);
        assert(big + 3U > big + 2U);

        assert(previous + 0U == previous);
        assert(previous + 1U == next);
        assert(previous + 2U > next);
        assert(previous + 3U == next + 2U);

        assert(next + 0U == next);
        assert(next + 1U > next);
        assert(next + 2U > next);
        assert(next + 3U >= next + two);

        assert(zero - zero == zero);
        assert(one - zero == one);
        assert(two - zero == two);
        assert(three - zero == three);
        assert(big - zero == big);
        assert(previous - zero == previous);
        assert(next - zero == next);

        assert(one - one == zero);
        assert(two - one == one);
        assert(three - one == two);
        assert(big - one < big);
        assert(previous - one < previous);
        assert(next - one == previous);

        assert(two - two == zero);
        assert(three - two == one);
        assert(big - two < big);
        assert(previous - two < previous);
        assert(next - two < previous);

        assert(three - three == zero);
        assert(big - three < big);
        assert(previous - three < previous);
        assert(next - three < previous);

        assert(big - big == zero);
        assert(next - previous == one);

        assert(one - 1U == zero);
        assert(two - 1U == one);
        assert(three - 1U == two);
        assert(big - 1U < big);
        assert(previous - 1U < previous);
        assert(next - 1U == previous);

        assert(two - 2U == zero);
        assert(three - 2U == one);
        assert(big - 2U < big);
        assert(previous - 2U < previous);
        assert(next - 2U < previous);

        assert(three - 3U == zero);
        assert(big - 3U < big);
        assert(previous - 3U < previous);
        assert(next - 3U < previous);

        T test = zero;
        assert(++test == one);
        assert(++test == two);
        assert(++test == three);
        test = big;
        assert(++test > big);
        test = previous;
        assert(++test == next);
        test = three;
        assert(--test == two);
        assert(--test == one);
        assert(--test == zero);
        test = big;
        assert(--test < big);
        test = next;
        assert(--test == previous);

        assert(-zero == zero);
        assert(-(-zero) == zero);
        assert(-(-one) == one);
        assert(-(-two) == two);
        assert(-(-three) == three);
        assert(-(-big) == big);
        assert(-(-previous) == previous);
        assert(-(-next) == next);

        for(auto i = 0; i < 10; ++i)
        {
            T a = rnd!T();
            T b = rnd!T();
            T.HALF c = rnd!(T.HALF)();
            ulong d = rnd!ulong();
            uint e = rnd!uint();

            T result = a / b;
            T remainder = a % b;

            assert(result * b + remainder == a);

            result = a / c;
            remainder = a % c;

            assert(result * c + remainder == a);

            result = a / d;
            remainder = a % d;

            assert(result * d + remainder == a);

            result = a / e;
            remainder = a % e;

            assert(result * e + remainder == a);
        }
    }

}

/* ****************************************************************************************************************** */
/* INTEGRAL UTILITY FUNCTIONS                                                                                         */
/* ****************************************************************************************************************** */

uint xadd(ref uint x, const(uint) y) @safe pure nothrow @nogc
{
    bool ovf;
    x = addu(x, y, ovf);
    return ovf ? 1 : 0;
}

uint xadd(ref ulong x, const(ulong) y) @safe pure nothrow @nogc
{
    bool ovf;
    x = addu(x, y, ovf);
    return ovf ? 1 : 0;
}

uint xadd(ref ulong x, const(uint) y) @safe pure nothrow @nogc
{
    return xadd(x, cast(ulong)y);
}

uint xadd(T)(ref T x, auto const ref T y) @safe pure nothrow @nogc
if (isCustomUnsignedBit!T)
{
    auto carry = xadd(x.lo, y.lo);
    carry = xadd(x.hi, carry);
    return xadd(x.hi, y.hi) + carry;
}

uint xadd(T, U)(ref T x, auto const ref U y) @safe pure nothrow @nogc
if (isCustomUnsignedBit!T && isUnsignedAssignableBit!(T.HALF, U))
{
    const carry = xadd(x.lo, y);
    return xadd(x.hi, carry);
}

@safe pure nothrow @nogc
uint xsub(ref uint x, const(uint) y)
{
    bool ovf;
    x = subu(x, y, ovf);
    return ovf ? 1 : 0;
}

@safe pure nothrow @nogc
uint xsub(ref ulong x, const(ulong) y)
{
    bool ovf;
    x = subu(x, y, ovf);
    return ovf ? 1 : 0;
}

@safe pure nothrow @nogc
uint xsub(ref ulong x, const(uint) y)
{
    return xsub(x, cast(ulong)y);
}

@safe pure nothrow @nogc
uint xsub(T)(ref T x, auto const ref T y)
if (isCustomUnsignedBit!T)
{
    auto carry = xsub(x.lo, y.lo);
    carry = xsub(x.hi, carry);
    return xsub(x.hi, y.hi) + carry;
}

@safe pure nothrow @nogc
uint xsub(T, U)(ref T x, auto const ref U y)
if (isCustomUnsignedBit!T && isUnsignedAssignableBit!(T.HALF, U))
{
    const carry = xsub(x.lo, y);
    return xsub(x.hi, carry);
}

uint fma(const(uint) x, const(uint) y, const(uint) z, ref bool overflow) @safe pure nothrow @nogc
{
    const result = mulu(x, y, overflow);
    return addu(result, z, overflow);
}

ulong fma(const(ulong) x, const(ulong) y, const(ulong) z, ref bool overflow) @safe pure nothrow @nogc
{
    const result = mulu(x, y, overflow);
    return addu(result, z, overflow);
}

ulong fma(const(ulong) x, const(uint) y, const(uint) z, ref bool overflow) @safe pure nothrow @nogc
{
    const result = mulu(x, cast(ulong)y, overflow);
    return addu(result, cast(ulong)z, overflow);
}

T fma(T)(auto const ref T x, auto const ref T y, auto const ref T z, ref bool overflow) @safe pure nothrow @nogc
if (isCustomUnsignedBit!T)
{
    auto result = mulu(x, y, overflow);
    if (xadd(result, z))
        overflow = true;
    return result;
}

T fma(T, U)(auto const ref T x, auto const ref U y, auto const ref U z, ref bool overflow) @safe pure nothrow @nogc
if (isCustomUnsignedBit!T && isUnsignedAssignableBit!(T.HALF, U))
{
    auto result = mulu(x, y, overflow);
    if (xadd(result, z))
        overflow = true;
    return result;
}

@safe pure nothrow @nogc
ulong xmul(const(uint) x, const(uint) y)
{
    return cast(ulong)x * y;
}

@safe pure nothrow @nogc
ulong xsqr(const(uint) x)
{
    return cast(ulong)x * x;
}

@safe pure nothrow @nogc
uint128 xmul(const(ulong) x, const(ulong) y)
{
    if (x == 0 || y == 0)
        return uint128.min;
    if (x == 1)
        return uint128(y);
    if (y == 1)
        return uint128(x);
    if ((x & (x - 1)) == 0)
        return uint128(y) << ctz(x);
    if ((y & (y - 1)) == 0)
        return uint128(x) << ctz(y);
    if (x == y)
        return xsqr(x);

    const xlo = cast(uint)x;
    const xhi = cast(uint)(x >>> 32);
    const ylo = cast(uint)y;
    const yhi = cast(uint)(y >>> 32);

    ulong t = xmul(xlo, ylo);
    const ulong w0 = cast(uint)t;
    ulong k = t >>> 32;

    t = xmul(xhi, ylo) + k;
    const ulong w1 = cast(uint)t;
    const ulong w2 = t >>> 32;

    t = xmul(xlo, yhi) + w1;
    k = t >>> 32;

    return uint128(xmul(xhi, yhi) + w2 + k, (t << 32) + w0);
}

@safe pure nothrow @nogc
uint128 xsqr(const(ulong) x)
{
    const xlo = cast(uint)x;
    const xhi = cast(uint)(x >>> 32);
    const hilo = xmul(xlo, xhi);

    ulong t = xsqr(xlo);
    const ulong w0 = cast(uint)t;
    ulong k = t >>> 32;

    t = hilo + k;
    const ulong w1 = cast(uint)t;
    const ulong w2 = t >>> 32;

    t = hilo + w1;
    k = t >>> 32;

    return uint128(xsqr(xhi) + w2 + k, (t << 32) + w0);
}

@safe pure nothrow @nogc
uint128 xmul(const(ulong) x, const(uint) y)
{
    if (x == 0 || y == 0)
        return uint128.min;
    if (x == 1)
        return uint128(y);
    if (y == 1)
        return uint128(x);
    if ((x & (x - 1)) == 0)
        return uint128(y) << ctz(x);
    if ((y & (y - 1)) == 0)
        return uint128(x) << ctz(y);

    const xlo = cast(uint)x;
    const xhi = cast(uint)(x >>> 32);

    ulong t = xmul(xlo, y);
    const ulong w0 = cast(uint)t;
    const ulong k = t >>> 32;

    t = xmul(xhi, y) + k;
    const ulong w1 = cast(uint)t;
    const ulong w2 = t >>> 32;

    return uint128(w2, (w1 << 32) + w0);
}

auto xmul(T)(auto const ref T x, auto const ref T y)
if (isCustomUnsignedBit!T)
{
    enum bits = T.sizeof * 8;
    alias R = UnsignedBit!(T.sizeof * 2);

    if (x == 0U || y == 0U)
        return R.min;
    if (x == 1U)
        return R(y);
    if (y == 1U)
        return R(x);
    if ((x & (x - 1U)) == 0U)
        return R(y) << ctz(x);
    if ((y & (y - 1U)) == 0U)
        return R(x) << ctz(y);
    if (x == y)
        return xsqr(x);

    auto t = xmul(x.lo, y.lo);
    const w0 = t.lo;
    const k = t.hi;

    t = xmul(x.hi, y.lo) + k;
    const w2 = t.hi;

    t = xmul(x.lo, y.hi) + t.lo;

    return R(xmul(x.hi, y.hi) + w2 + t.hi, (t << (bits / 2)) + w0);
}

T mulu(T)(auto const ref T x, auto const ref T y, ref bool overflow)
if (isCustomUnsignedBit!T)
{
    enum bits = T.sizeof * 8;

    if (x == 0U || y == 0U)
        return T.min;
    if (x == 1)
        return y;
    if (y == 1)
        return x;
    if ((x & (x - 1)) == 0U)
    {
        const lz = clz(y);
        const shift = ctz(x);
        if (lz < shift)
            overflow = true;
        return y << shift;
    }
    if ((y & (y - 1)) == 0U)
    {
        const lz = clz(x);
        const shift = ctz(y);
        if (lz < shift)
            overflow = true;
        return x << shift;
    }
    if (x == y)
        return sqru(x, overflow);

    auto t = xmul(x.lo, y.lo);
    const w0 = t.lo;
    const k = t.hi;

    t = xmul(x.hi, y.lo) + k;
    const w2 = t.hi;

    t = xmul(x.lo, y.hi) + t.lo;

    if (w2 || t.hi)
        overflow = true;
    else if (xmul(x.hi, y.hi))
        overflow = true;

    return (t << (bits / 2)) + w0;
}

auto xsqr(T)(auto const ref T x)
if (isCustomUnsignedBit!T)
{
    enum bits = T.sizeof * 8;
    alias R = UnsignedBit!(T.sizeof * 2);

    const hilo = xmul(x.lo, x.hi);

    auto t = xsqr(x.lo);
    const w0 = t.lo;
    const k = t.hi;

    t = hilo + k;
    const w2 = t.hi;

    t = hilo + t.lo;

    return R(xsqr(x.hi) + w2 + t.hi, (t << (bits / 2)) + w0);
}

T sqru(T)(auto const ref T x, ref bool overflow)
if (isCustomUnsignedBit!T)
{
    enum bits = T.sizeof * 8;

    const hilo = xmul(x.lo, x.hi);
    auto t = xsqr(x.lo);
    const w0 = t.lo;
    const k = t.hi;

    t = hilo + k;
    const w2 = t.hi;

    t = hilo + t.lo;

    if (w2 || t.hi)
        overflow = true;
    else if (xhi)
        overflow = true;

    return (t << (bits / 2)) + w0;
}

auto xmul(T, U)(auto const ref T x, auto const ref U y)
if (isCustomUnsignedBit!T && isUnsignedAssignableBit!(T.HALF, U))
{
    enum bits = T.sizeof * 8;
    alias R = UnsignedBit!(T.sizeof * 2);

    if (x == 0U || y == 0U)
        return R.min;
    if (x == 1U)
        return R(y);
    if (y == 1U)
        return R(x);
    if ((x & (x - 1U)) == 0U)
        return R(y) << ctz(x);
    if ((y & (y - 1U)) == 0U)
        return R(x) << ctz(y);

    auto t = xmul(x.lo, y);
    const w0 = t.lo;
    const k = t.hi;

    t = xmul(x.hi, y) + k;
    const w2 = t.hi;

    t = t.lo;

    return R(w2, (t << (bits / 2)) + w0);
}

T mulu(T, U)(auto const ref T x, auto const ref U y, ref bool overflow)
if (isCustomUnsignedBit!T && isUnsignedAssignableBit!(T.HALF, U))
{
    enum bits = T.sizeof * 8;

    if (x == 0U || y == 0U)
        return T.min;
    if (x == 1U)
        return T(y);
    if (y == 1U)
        return x;
    if ((x & (x - 1U)) == 0U)
    {
        const yy = T(y);
        const lz = clz(y);
        const shift = ctz(x);
        if (lz < shift)
            overflow = true;
        return yy << shift;
    }
    if ((y & (y - 1)) == 0U)
    {
        const lz = clz(x);
        const shift = ctz(y);
        if (lz < shift)
            overflow = true;
        return x << shift;
    }

    auto t = xmul(x.lo, y);
    const w0 = t.lo;
    const k = t.hi;

    t = xmul(x.hi, y) + k;

    if (t.hi)
        overflow = true;

    t = t.lo;

    return (t << (bits / 2)) + w0;
}

@safe pure nothrow @nogc
auto clz(const(uint) x)
{
    return x ? 31 - bsr(x) : 0;
}

@safe pure nothrow @nogc
auto clz(const(ulong) x)
{
    if (!x)
        return 64;
    static if (is(size_t == ulong))
        return 63 - bsr(x);
    else static if(is(size_t == uint))
    {
        const hi = cast(uint)(x >> 32);
        if (hi)
            return 31 - bsr(hi);
        else
            return 63 - bsr(cast(uint)x);
    }
    else
        static assert(0);
}

auto clz(T)(auto const ref T x)
if (isCustomUnsignedBit!T)
{
    enum bits = T.sizeof * 8;
    auto ret = clz(x.hi);
    return ret == bits / 2 ? ret + clz(x.lo) : ret;
}

@safe pure nothrow @nogc
auto ctz(const(uint) x)
{
    return x ? bsf(x) : 0;
}

@safe pure nothrow @nogc
auto ctz(const(ulong) x)
{
    if (!x)
        return 64;
    static if (is(size_t == ulong))
        return bsf(x);
    else static if (is(size_t == uint))
    {
        const lo = cast(uint)x;
        if (lo)
            return bsf(lo);
        else
            return bsf(cast(uint)(x >> 32)) + 32;
    }
    else
        static assert(0);
}

auto ctz(T)(auto const ref T x)
if (isCustomUnsignedBit!T)
{
    enum bits = T.sizeof * 8;
    auto ret = ctz(x.lo);
    return ret == bits / 2 ? ret + ctz(x.hi) : ret;
}

bool isPow2(T)(auto const ref T x)
if (isAnyUnsignedBit!T)
{
    return x != 0U && (x & (x - 1U)) == 0;
}

bool isPow10(T)(auto const ref T x)
if (isAnyUnsignedBit!T)
{
    if (x == 0U)
        return false;

    for (size_t i = 0; i < pow10!T.length; ++i)
    {
        if (x == pow10!T[i])
            return true;
        else if (x < pow10!T[i])
            return false;
    }
    return false;
}

@safe pure nothrow @nogc
uint divrem(ref uint x, const(uint) y)
{
    uint ret = x % y;
    x /= y;
    return ret;
}

@safe pure nothrow @nogc
ulong divrem(ref ulong x, const(ulong) y)
{
    ulong ret = x % y;
    x /= y;
    return ret;
}

@safe pure nothrow @nogc
ulong divrem(ref ulong x, const(uint) y)
{
    ulong ret = x % y;
    x /= y;
    return ret;
}

T divrem(T)(ref T x, auto const ref T y)
if (isCustomUnsignedBit!T)
{
    alias UT = Unqual!T;
    UT r;

    if (!x.hi)
    {
        if (!y.hi)
            return UT(divrem(x.lo, y.lo));
        r.lo = x.lo;
        x.lo = 0U;
        return r;
    }

    if (!y.lo)
    {
        if (!y.hi)
            return UT(divrem(x.hi, y.lo));
        if (!x.lo)
        {
            r.hi = divrem(x.hi, y.hi);
            x.lo = x.hi;
            x.hi = 0U;
            return r;
        }
        if ((y.hi & (y.hi - 1U)) == 0U)
        {
            r.lo = x.lo;
            r.hi = x.hi & (y.hi - 1U);
            x.lo = x.hi >>> ctz(y.hi);
            x.hi = 0U;
            return r;
        }
        const shift = clz(y.hi) - clz(x.hi);
        if (shift > T.HALF.sizeof * 8 - 2)
        {
            r = x;
            x = 0U;
            return r;
        }
    }
    else
    {
        if (!y.hi)
        {
            if ((y.lo & (y.lo - 1U)) == 0U)
            {
                r.lo = x.lo & (y.lo - 1U);
                if (y.lo == 1U)
                    return r;
                x >>= ctz(y.lo);
                return r;
            }
        }
        else
        {
            const shift = clz(y.hi) - clz(x.hi);
            if (shift > T.HALF.sizeof * 8 - 1)
            {
                r = x;
                x = 0U;
                return r;
            }
        }
    }

    r = x;
    T d = y;
    T z = 1U;
    x = 0U;

    const shift = clz(d);

    z <<= shift;
    d <<= shift;

    while(z)
    {
        if (r >= d)
        {
            r -= d;
            x |= z;
        }
        z >>= 1;
        d >>= 1;
    }

    return r;
}

T divrem(T, U)(ref T x, auto const ref U y)
if (isCustomUnsignedBit!T && isUnsignedAssignableBit!(T.HALF, U))
{
    alias UT = Unqual!T;
    UT r;

    if (!x.hi)
        return UT(divrem(x.lo, y));

    if (!y)
        return UT(divrem(x.hi, y));

    if ((y & (y - 1U)) == 0U)
    {
        r.lo = x.lo & (y - 1U);
        if (y == 1U)
            return r;
        x >>= ctz(y);
        return r;
    }

    r = x;
    T d = y;
    T z = 1U;
    x = 0U;

    const shift = clz(d);

    z <<= shift;
    d <<= shift;

    while(z)
    {
        if (r >= d)
        {
            r -= d;
            x |= z;
        }
        z >>= 1;
        d >>= 1;
    }

    return r;
}

int prec(T)(const(T) x)
if (isUnsigned!T || is(T : uint128) || is(T : uint256) || is(T : uint512))
{
    static foreach_reverse(i, p; pow10!T)
    {
        if (x >= p)
            return i + 1;
    }
    return 0;
}

//returns power of 10 if x is power of 10, -1 otherwise
@safe pure nothrow @nogc
int getPow10(T)(auto const ref T x)
if (isUnsigned!T || is(T : uint128) || is(T : uint256))
{
    static foreach_reverse(i, p; pow10!T)
    {
        if (x == p)
            return i + 1;
        else if (x < p)
            return -1;
    }
    return 0;
}

T cvt(T, U)(auto const ref U value)
if (isAnyUnsignedBit!T && isAnyUnsignedBit!U)
{
    static if (T.sizeof > U.sizeof)
        return (T(value));
    else static if (T.sizeof < U.sizeof)
        return cast(T)(value);
    else
        return value;
}

auto sign(S, U)(const(U) u, const(bool) isNegative)
if (isUnsigned!U && isSigned!S)
{
    static if (is(U: ubyte) || is(U: ushort))
        return isNegative ? cast(S)-cast(int)u : cast(S)u;
    else static if (is(S: byte) || is(S: short))
        return isNegative ? cast(S)-cast(int)u : cast(S)u;
    else
        return isNegative ? -cast(S)u : cast(S)u;
}

unittest
{
    static assert(sign!byte(ubyte(128), true) == byte.min);
    static assert(sign!byte(ushort(128), true) == byte.min);
    static assert(sign!byte(uint(128), true) == byte.min);
    static assert(sign!byte(ulong(128), true) == byte.min);

    static assert(sign!short(ubyte(128), true) == byte.min);
    static assert(sign!short(ushort(32768), true) == short.min);
    static assert(sign!short(uint(32768), true) == short.min);
    static assert(sign!short(ulong(32768), true) == short.min);

    static assert(sign!int(ubyte(128), true) == byte.min);
    static assert(sign!int(ushort(32768), true) == short.min);
    static assert(sign!int(uint(2147483648), true) == int.min);
    static assert(sign!int(ulong(2147483648), true) == int.min);

    static assert(sign!long(ubyte(128), true) == byte.min);
    static assert(sign!long(ushort(32768), true) == short.min);
    static assert(sign!long(uint(2147483648), true) == int.min);
    static assert(sign!long(ulong(9223372036854775808UL), true) == long.min);
}

auto sign(S, U)(const(U) u, const(bool) isNegative)
if (isCustomUnsignedBit!U && isSigned!S)
{
    return isNegative ? cast(S)-cast(ulong)u : cast(S)cast(ulong)u;
}

auto unsign(U, S)(const(S) s, out bool isNegative)
if (isUnsigned!U && isSigned!S)
{
    isNegative = s < 0;
    static if (is(S: byte) || is(S: short))
        return isNegative ? cast(U)-cast(int)s : cast(U)s;
    else static if (is(U: ubyte) || is(U: ushort))
        return isNegative ? cast(U)-cast(int)s : cast(U)s;
    else
        return isNegative? -cast(U)s: cast(U)s;
}

unittest
{
    static assert(unsign!ubyte(byte.min) == 128);
    static assert(unsign!ubyte(short(-128)) == 128);
    static assert(unsign!ubyte(int(-128)) == 128);
    static assert(unsign!ubyte(long(-128)) == 128);

    static assert(unsign!ushort(byte.min) == 128);
    static assert(unsign!ushort(short.min) == 32768);
    static assert(unsign!ushort(int(short.min)) == 32768);
    static assert(unsign!ushort(long(short.min)) == 32768);

    static assert(unsign!uint(byte.min) == 128);
    static assert(unsign!uint(short.min) == 32768);
    static assert(unsign!uint(int.min) == 2147483648);
    static assert(unsign!uint(long(int.min)) == 2147483648);

    static assert(unsign!ulong(byte.min) == 128);
    static assert(unsign!ulong(short.min) == 32768);
    static assert(unsign!ulong(int.min) == 2147483648);
    static assert(unsign!ulong(long.min) == 9223372036854775808UL);
}

auto unsign(U, V)(const(V) v, out bool isNegative)
if (isUnsigned!U && isUnsigned!V)
{
    isNegative = false;
    return cast(U)v;
}

auto unsign(U, V)(const(V) v, out bool isNegative)
if (isCustomUnsignedBit!U && isUnsigned!V)
{
    isNegative = false;
    return U(v);
}

auto unsign(U, S)(const(S) s)
if (isUnsigned!U && isSigned!S)
{
    static if (is(S: byte) || is(S: short))
        return s < 0 ? cast(U)-cast(int)s : cast(U)s;
    else static if (is(U: ubyte) || is(U: ushort))
        return s < 0 ? cast(U)-cast(int)s : cast(U)s;
    else
        return s < 0 ? -cast(U)s: cast(U)s;
}

auto unsign(U, S)(const(S) s, out bool isNegative)
if (isCustomUnsignedBit!U && isSigned!S)
{
    isNegative = s < 0;
    static if (is(S: byte) || is(S: short))
        return isNegative ? U(cast(uint)-cast(int)s) : U(cast(uint)s);
    else static if (is(S: int))
        return isNegative ? U(cast(ulong)(-cast(long)s)) : U(cast(uint)s);
    else
        return isNegative ? U(cast(ulong)-s) : U(cast(ulong)s);
}

auto unsign(U, S)(const(S) s)
if (isCustomUnsignedBit!U && isSigned!S)
{
    static if (is(S: byte) || is(S: short))
        return s < 0 ? U(cast(uint)-cast(int)s) : U(cast(uint)s);
    else static if (is(S: int))
        return s < 0 ? U(cast(ulong)(-cast(long)s)) : U(cast(uint)s);
    else
        return s < 0 ? U(cast(ulong)-s) : U(cast(ulong)s);
}

int cappedAdd(ref int target, const(int) value) pure @safe nothrow @nogc
{
    bool ovf;
    int result = adds(target, value, ovf);
    if (ovf)
    {
        if (value > 0)
        {
            //target was positive
            result = int.max - target;
            target = int.max;
        }
        else
        {
            //target was negative
            result = int.min - target;
            target = int.min;
        }
        return result;
    }
    else
    {
        target += value;
        return value;
    }
}

int cappedSub(ref int target, const(int) value) pure @safe nothrow @nogc
{
    bool ovf;
    int result = subs(target, value, ovf);
    if (ovf)
    {
        if (value > 0)
        {
            //target was negative
            result = target - int.min;
            target = int.min;
        }
        else
        {
            //target was positive
            result = target - int.max;
            target = int.max;
        }
        return result;
    }
    else
    {
        target -= value;
        return value;
    }
}

unittest
{
    int ex = int.min + 1;
    int px = cappedSub(ex, 3);
    assert(ex == int.min);
    assert(px == 1);

    ex = int.min + 3;
    px = cappedSub(ex, 2);
    assert(ex == int.min + 1);
    assert(px == 2);

    ex = int.max - 1;
    px = cappedSub(ex, -2);
    assert(ex == int.max);
    assert(px == -1);

    ex = int.max - 3;
    px = cappedSub(ex, -2);
    assert(ex == int.max - 1);
    assert(px == -2);
}

/* ****************************************************************************************************************** */
/* 10-POWER CONSTANTS                                                                                                 */
/* ****************************************************************************************************************** */

static immutable ubyte[3] pow10_8 = [
    1U,
    10U,
    100U,
    ];

static immutable ushort[5] pow10_16 = [
    1U,
    10U,
    100U,
    1000U,
    10000U,
    ];

static immutable uint[10] pow10_32 = [
    1U,
    10U,
    100U,
    1000U,
    10000U,
    100000U,
    1000000U,
    10000000U,
    100000000U,
    1000000000U,
    ];

static immutable ulong[20] pow10_64 = [
    1UL,
    10UL,
    100UL,
    1000UL,
    10000UL,
    100000UL,
    1000000UL,
    10000000UL,
    100000000UL,
    1000000000UL,
    10000000000UL,
    100000000000UL,
    1000000000000UL,
    10000000000000UL,
    100000000000000UL,
    1000000000000000UL,
    10000000000000000UL,
    100000000000000000UL,
    1000000000000000000UL,
    10000000000000000000UL,
    ];

static immutable uint128[39] pow10_128 = [
    uint128(1UL),
    uint128(10UL),
    uint128(100UL),
    uint128(1000UL),
    uint128(10000UL), // 4
    uint128(100000UL),
    uint128(1000000UL),
    uint128(10000000UL),
    uint128(100000000UL),
    uint128(1000000000UL), // 9
    uint128(10000000000UL),
    uint128(100000000000UL),
    uint128(1000000000000UL),
    uint128(10000000000000UL),
    uint128(100000000000000UL), // 14
    uint128(1000000000000000UL),
    uint128(10000000000000000UL),
    uint128(100000000000000000UL),
    uint128(1000000000000000000UL),
    uint128(10000000000000000000UL), // 19
    uint128(cast(const(ubyte)[])[5, 107, 199, 94, 45, 99, 16, 0, 0]),          // uint128("100000000000000000000"), // 20
    uint128(cast(const(ubyte)[])[54, 53, 201, 173, 197, 222, 160, 0, 0]),      // uint128("1000000000000000000000"),
    uint128(cast(const(ubyte)[])[2, 30, 25, 224, 201, 186, 178, 64, 0, 0]),       // uint128("10000000000000000000000"),
    uint128(cast(const(ubyte)[])[21, 45, 2, 199, 225, 74, 246, 128, 0, 0]),       // uint128("100000000000000000000000"),
    uint128(cast(const(ubyte)[])[211, 194, 27, 206, 204, 237, 161, 0, 0, 0]),     // uint128("1000000000000000000000000"),
    uint128(cast(const(ubyte)[])[8, 69, 149, 22, 20, 1, 72, 74, 0, 0, 0]),           // uint128("10000000000000000000000000"),
    uint128(cast(const(ubyte)[])[82, 183, 210, 220, 200, 12, 210, 228, 0, 0, 0]),    // uint128("100000000000000000000000000"),
    uint128(cast(const(ubyte)[])[3, 59, 46, 60, 159, 208, 128, 60, 232, 0, 0, 0]),      // uint128("1000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[32, 79, 206, 94, 62, 37, 2, 97, 16, 0, 0, 0]),         // uint128("10000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[1, 67, 30, 15, 174, 109, 114, 23, 202, 160, 0, 0, 0]),    // uint128("100000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[12, 159, 44, 156, 208, 70, 116, 237, 234, 64, 0, 0, 0]),  // uint128("1000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[126, 55, 190, 32, 34, 192, 145, 75, 38, 128, 0, 0, 0]),   // uint128("10000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[4, 238, 45, 109, 65, 91, 133, 172, 239, 129, 0, 0, 0, 0]),   // uint128("100000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[49, 77, 198, 68, 141, 147, 56, 193, 91, 10, 0, 0, 0, 0]),    // uint128("1000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[1, 237, 9, 190, 173, 135, 192, 55, 141, 142, 100, 0, 0, 0, 0]), // uint128("10000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[19, 66, 97, 114, 199, 77, 130, 43, 135, 143, 232, 0, 0, 0, 0]), // uint128("100000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[192, 151, 206, 123, 201, 7, 21, 179, 75, 159, 16, 0, 0, 0, 0]), // uint128("1000000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[7, 133, 238, 16, 213, 218, 70, 217, 0, 244, 54, 160, 0, 0, 0, 0]), // uint128("10000000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[75, 59, 76, 168, 90, 134, 196, 122, 9, 138, 34, 64, 0, 0, 0, 0]),  // uint128("100000000000000000000000000000000000000"),
    ];

version(ShowEnumDecBytes)
unittest
{
    static assert(pow10_128[0 + 20]  == uint128("100000000000000000000"));
    static assert(pow10_128[1 + 20]  == uint128("1000000000000000000000"));
    static assert(pow10_128[2 + 20]  == uint128("10000000000000000000000"));
    static assert(pow10_128[3 + 20]  == uint128("100000000000000000000000"));
    static assert(pow10_128[4 + 20]  == uint128("1000000000000000000000000"));
    static assert(pow10_128[5 + 20]  == uint128("10000000000000000000000000"));
    static assert(pow10_128[6 + 20]  == uint128("100000000000000000000000000"));
    static assert(pow10_128[7 + 20]  == uint128("1000000000000000000000000000"));
    static assert(pow10_128[8 + 20]  == uint128("10000000000000000000000000000"));
    static assert(pow10_128[9 + 20]  == uint128("100000000000000000000000000000"));
    static assert(pow10_128[10 + 20] == uint128("1000000000000000000000000000000"));
    static assert(pow10_128[11 + 20] == uint128("10000000000000000000000000000000"));
    static assert(pow10_128[12 + 20] == uint128("100000000000000000000000000000000"));
    static assert(pow10_128[13 + 20] == uint128("1000000000000000000000000000000000"));
    static assert(pow10_128[14 + 20] == uint128("10000000000000000000000000000000000"));
    static assert(pow10_128[15 + 20] == uint128("100000000000000000000000000000000000"));
    static assert(pow10_128[16 + 20] == uint128("1000000000000000000000000000000000000"));
    static assert(pow10_128[17 + 20] == uint128("10000000000000000000000000000000000000"));
    static assert(pow10_128[18 + 20] == uint128("100000000000000000000000000000000000000"));
}

static immutable uint256[78] pow10_256 = [
    uint256(1UL),
    uint256(10UL),
    uint256(100UL),
    uint256(1000UL),
    uint256(10000UL), // 4
    uint256(100000UL),
    uint256(1000000UL),
    uint256(10000000UL),
    uint256(100000000UL),
    uint256(1000000000UL), // 9
    uint256(10000000000UL),
    uint256(100000000000UL),
    uint256(1000000000000UL),
    uint256(10000000000000UL),
    uint256(100000000000000UL), // 14
    uint256(1000000000000000UL),
    uint256(10000000000000000UL),
    uint256(100000000000000000UL),
    uint256(1000000000000000000UL),
    uint256(10000000000000000000UL), // 19
    uint256(cast(const(ubyte)[])[5, 107, 199, 94, 45, 99, 16, 0, 0]), // uint256("100000000000000000000"), // 20
    uint256(cast(const(ubyte)[])[54, 53, 201, 173, 197, 222, 160, 0, 0]), // uint256("1000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 30, 25, 224, 201, 186, 178, 64, 0, 0]), // uint256("10000000000000000000000"),
    uint256(cast(const(ubyte)[])[21, 45, 2, 199, 225, 74, 246, 128, 0, 0]), // uint256("100000000000000000000000"),
    uint256(cast(const(ubyte)[])[211, 194, 27, 206, 204, 237, 161, 0, 0, 0]), // uint256("1000000000000000000000000"),
    uint256(cast(const(ubyte)[])[8, 69, 149, 22, 20, 1, 72, 74, 0, 0, 0]), // uint256("10000000000000000000000000"),
    uint256(cast(const(ubyte)[])[82, 183, 210, 220, 200, 12, 210, 228, 0, 0, 0]), // uint256("100000000000000000000000000"),
    uint256(cast(const(ubyte)[])[3, 59, 46, 60, 159, 208, 128, 60, 232, 0, 0, 0]), // uint256("1000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[32, 79, 206, 94, 62, 37, 2, 97, 16, 0, 0, 0]), // uint256("10000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 67, 30, 15, 174, 109, 114, 23, 202, 160, 0, 0, 0]), // uint256("100000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[12, 159, 44, 156, 208, 70, 116, 237, 234, 64, 0, 0, 0]), // uint256("1000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[126, 55, 190, 32, 34, 192, 145, 75, 38, 128, 0, 0, 0]), // uint256("10000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[4, 238, 45, 109, 65, 91, 133, 172, 239, 129, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[49, 77, 198, 68, 141, 147, 56, 193, 91, 10, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 237, 9, 190, 173, 135, 192, 55, 141, 142, 100, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[19, 66, 97, 114, 199, 77, 130, 43, 135, 143, 232, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[192, 151, 206, 123, 201, 7, 21, 179, 75, 159, 16, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[7, 133, 238, 16, 213, 218, 70, 217, 0, 244, 54, 160, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[75, 59, 76, 168, 90, 134, 196, 122, 9, 138, 34, 64, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 240, 80, 254, 147, 137, 67, 172, 196, 95, 101, 86, 128, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[29, 99, 41, 241, 195, 92, 164, 191, 171, 185, 245, 97, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 37, 223, 163, 113, 161, 158, 111, 124, 181, 67, 149, 202, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[11, 122, 188, 98, 112, 80, 48, 90, 223, 20, 163, 217, 228, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[114, 203, 91, 216, 99, 33, 227, 140, 182, 206, 102, 130, 232, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[4, 123, 241, 150, 115, 223, 82, 227, 127, 36, 16, 1, 29, 16, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[44, 215, 111, 224, 134, 185, 60, 226, 247, 104, 160, 11, 34, 160, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 192, 106, 94, 197, 67, 60, 96, 221, 170, 22, 64, 111, 90, 64, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[17, 132, 39, 179, 180, 160, 91, 200, 168, 164, 222, 132, 89, 134, 128, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[175, 41, 141, 5, 14, 67, 149, 214, 150, 112, 177, 43, 127, 65, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[6, 215, 159, 130, 50, 142, 163, 218, 97, 224, 102, 235, 178, 248, 138, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[68, 108, 59, 21, 249, 146, 102, 135, 210, 196, 5, 52, 253, 181, 100, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 172, 58, 78, 219, 191, 184, 1, 78, 59, 168, 52, 17, 233, 21, 232, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[26, 186, 71, 20, 149, 125, 48, 13, 14, 84, 146, 8, 179, 26, 219, 16, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 11, 70, 198, 205, 214, 227, 224, 130, 143, 77, 180, 86, 255, 12, 142, 160, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[10, 112, 195, 196, 10, 100, 230, 197, 25, 153, 9, 11, 101, 246, 125, 146, 64, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[104, 103, 165, 168, 103, 241, 3, 178, 255, 250, 90, 113, 251, 160, 231, 182, 128, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[4, 20, 12, 120, 148, 15, 106, 36, 253, 255, 199, 136, 115, 212, 73, 13, 33, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[40, 200, 124, 181, 200, 154, 37, 113, 235, 253, 203, 84, 134, 74, 218, 131, 74, 0, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 151, 212, 223, 25, 214, 5, 118, 115, 55, 233, 241, 77, 62, 236, 137, 32, 228, 0, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[15, 238, 80, 183, 2, 92, 54, 160, 128, 47, 35, 109, 4, 117, 61, 91, 72, 232, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[159, 79, 39, 38, 23, 154, 34, 69, 1, 215, 98, 66, 44, 148, 101, 144, 217, 16, 0, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[6, 57, 23, 135, 124, 236, 5, 86, 178, 18, 105, 214, 149, 189, 203, 247, 168, 122, 160, 0, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[62, 58, 235, 74, 225, 56, 53, 98, 244, 184, 34, 97, 217, 105, 247, 172, 148, 202, 64, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 110, 77, 48, 236, 204, 50, 21, 221, 143, 49, 87, 210, 126, 35, 172, 189, 207, 230, 128, 0, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[24, 79, 3, 233, 63, 249, 244, 218, 167, 151, 237, 110, 56, 237, 100, 191, 106, 31, 1, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[243, 22, 39, 28, 127, 195, 144, 138, 139, 239, 70, 78, 57, 69, 239, 122, 37, 54, 10, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[9, 126, 221, 135, 28, 253, 163, 165, 105, 119, 88, 191, 14, 60, 187, 90, 197, 116, 28, 100, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[94, 244, 167, 71, 33, 232, 100, 118, 30, 169, 119, 118, 142, 95, 81, 139, 182, 137, 27, 232, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[3, 181, 142, 136, 199, 83, 19, 236, 157, 50, 158, 170, 161, 143, 185, 47, 117, 33, 91, 23, 16, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[37, 23, 145, 87, 201, 62, 199, 62, 35, 250, 50, 170, 79, 157, 59, 218, 147, 77, 142, 230, 160, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 114, 235, 173, 109, 220, 115, 200, 109, 103, 197, 250, 167, 28, 36, 86, 137, 193, 7, 149, 2, 64, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[14, 125, 52, 198, 74, 156, 133, 212, 70, 13, 187, 202, 135, 25, 107, 97, 97, 138, 75, 210, 22, 128, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[144, 228, 15, 190, 234, 29, 58, 74, 188, 137, 85, 233, 70, 254, 49, 205, 207, 102, 246, 52, 225, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[5, 168, 232, 157, 117, 37, 36, 70, 235, 93, 93, 91, 28, 197, 237, 242, 10, 26, 5, 158, 16, 202, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[56, 153, 22, 38, 147, 115, 106, 197, 49, 165, 165, 143, 31, 187, 75, 116, 101, 4, 56, 44, 167, 228, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 53, 250, 221, 129, 194, 130, 43, 179, 240, 120, 119, 151, 61, 80, 242, 139, 242, 42, 49, 190, 142, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("1000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[22, 27, 204, 167, 17, 153, 21, 181, 7, 100, 180, 171, 232, 101, 41, 121, 119, 117, 165, 241, 113, 149, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("10000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[221, 21, 254, 134, 175, 250, 217, 18, 73, 239, 14, 183, 19, 243, 158, 190, 170, 152, 123, 110, 111, 210, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000000000000000000000000"),
    ];

version(ShowEnumDecBytes)
unittest
{
    static assert(pow10_256[0 + 20]  == uint256("100000000000000000000")); // 20
    static assert(pow10_256[1 + 20]  == uint256("1000000000000000000000"));
    static assert(pow10_256[2 + 20]  == uint256("10000000000000000000000"));
    static assert(pow10_256[3 + 20]  == uint256("100000000000000000000000"));
    static assert(pow10_256[4 + 20]  == uint256("1000000000000000000000000"));
    static assert(pow10_256[5 + 20]  == uint256("10000000000000000000000000"));
    static assert(pow10_256[6 + 20]  == uint256("100000000000000000000000000"));
    static assert(pow10_256[7 + 20]  == uint256("1000000000000000000000000000"));
    static assert(pow10_256[8 + 20]  == uint256("10000000000000000000000000000"));
    static assert(pow10_256[9 + 20]  == uint256("100000000000000000000000000000"));
    static assert(pow10_256[10 + 20] == uint256("1000000000000000000000000000000"));
    static assert(pow10_256[11 + 20] == uint256("10000000000000000000000000000000"));
    static assert(pow10_256[12 + 20] == uint256("100000000000000000000000000000000"));
    static assert(pow10_256[13 + 20] == uint256("1000000000000000000000000000000000"));
    static assert(pow10_256[14 + 20] == uint256("10000000000000000000000000000000000"));
    static assert(pow10_256[15 + 20] == uint256("100000000000000000000000000000000000"));
    static assert(pow10_256[16 + 20] == uint256("1000000000000000000000000000000000000"));
    static assert(pow10_256[17 + 20] == uint256("10000000000000000000000000000000000000"));
    static assert(pow10_256[18 + 20] == uint256("100000000000000000000000000000000000000"));
    static assert(pow10_256[19 + 20] == uint256("1000000000000000000000000000000000000000"));
    static assert(pow10_256[20 + 20] == uint256("10000000000000000000000000000000000000000"));
    static assert(pow10_256[21 + 20] == uint256("100000000000000000000000000000000000000000"));
    static assert(pow10_256[22 + 20] == uint256("1000000000000000000000000000000000000000000"));
    static assert(pow10_256[23 + 20] == uint256("10000000000000000000000000000000000000000000"));
    static assert(pow10_256[24 + 20] == uint256("100000000000000000000000000000000000000000000"));
    static assert(pow10_256[25 + 20] == uint256("1000000000000000000000000000000000000000000000"));
    static assert(pow10_256[26 + 20] == uint256("10000000000000000000000000000000000000000000000"));
    static assert(pow10_256[27 + 20] == uint256("100000000000000000000000000000000000000000000000"));
    static assert(pow10_256[28 + 20] == uint256("1000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[29 + 20] == uint256("10000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[30 + 20] == uint256("100000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[31 + 20] == uint256("1000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[32 + 20] == uint256("10000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[33 + 20] == uint256("100000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[34 + 20] == uint256("1000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[35 + 20] == uint256("10000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[36 + 20] == uint256("100000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[37 + 20] == uint256("1000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[38 + 20] == uint256("10000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[39 + 20] == uint256("100000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[40 + 20] == uint256("1000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[41 + 20] == uint256("10000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[42 + 20] == uint256("100000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[43 + 20] == uint256("1000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[44 + 20] == uint256("10000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[45 + 20] == uint256("100000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[46 + 20] == uint256("1000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[47 + 20] == uint256("10000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[48 + 20] == uint256("100000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[49 + 20] == uint256("1000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[50 + 20] == uint256("10000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[51 + 20] == uint256("100000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[52 + 20] == uint256("1000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[53 + 20] == uint256("10000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[54 + 20] == uint256("100000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[55 + 20] == uint256("1000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[56 + 20] == uint256("10000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_256[57 + 20] == uint256("100000000000000000000000000000000000000000000000000000000000000000000000000000"));
}

static immutable uint512[155] pow10_512 = [
    uint512(1UL),
    uint512(10UL),
    uint512(100UL),
    uint512(1000UL),
    uint512(10000UL), // 4
    uint512(100000UL),
    uint512(1000000UL),
    uint512(10000000UL),
    uint512(100000000UL),
    uint512(1000000000UL), // 9
    uint512(10000000000UL),
    uint512(100000000000UL),
    uint512(1000000000000UL),
    uint512(10000000000000UL),
    uint512(100000000000000UL), // 14
    uint512(1000000000000000UL),
    uint512(10000000000000000UL),
    uint512(100000000000000000UL),
    uint512(1000000000000000000UL),
    uint512(10000000000000000000UL), // 19
    uint512(cast(const(ubyte)[])[5, 107, 199, 94, 45, 99, 16, 0, 0]), // uint512("100000000000000000000"), // 20
    uint512(cast(const(ubyte)[])[54, 53, 201, 173, 197, 222, 160, 0, 0]), // uint512("1000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 30, 25, 224, 201, 186, 178, 64, 0, 0]), // uint512("10000000000000000000000"),
    uint512(cast(const(ubyte)[])[21, 45, 2, 199, 225, 74, 246, 128, 0, 0]), // uint512("100000000000000000000000"),
    uint512(cast(const(ubyte)[])[211, 194, 27, 206, 204, 237, 161, 0, 0, 0]), // uint512("1000000000000000000000000"),
    uint512(cast(const(ubyte)[])[8, 69, 149, 22, 20, 1, 72, 74, 0, 0, 0]), // uint512("10000000000000000000000000"),
    uint512(cast(const(ubyte)[])[82, 183, 210, 220, 200, 12, 210, 228, 0, 0, 0]), // uint512("100000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 59, 46, 60, 159, 208, 128, 60, 232, 0, 0, 0]), // uint512("1000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[32, 79, 206, 94, 62, 37, 2, 97, 16, 0, 0, 0]), // uint512("10000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 67, 30, 15, 174, 109, 114, 23, 202, 160, 0, 0, 0]), // uint512("100000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[12, 159, 44, 156, 208, 70, 116, 237, 234, 64, 0, 0, 0]), // uint512("1000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[126, 55, 190, 32, 34, 192, 145, 75, 38, 128, 0, 0, 0]), // uint512("10000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 238, 45, 109, 65, 91, 133, 172, 239, 129, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[49, 77, 198, 68, 141, 147, 56, 193, 91, 10, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 237, 9, 190, 173, 135, 192, 55, 141, 142, 100, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[19, 66, 97, 114, 199, 77, 130, 43, 135, 143, 232, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[192, 151, 206, 123, 201, 7, 21, 179, 75, 159, 16, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[7, 133, 238, 16, 213, 218, 70, 217, 0, 244, 54, 160, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[75, 59, 76, 168, 90, 134, 196, 122, 9, 138, 34, 64, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 240, 80, 254, 147, 137, 67, 172, 196, 95, 101, 86, 128, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[29, 99, 41, 241, 195, 92, 164, 191, 171, 185, 245, 97, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 37, 223, 163, 113, 161, 158, 111, 124, 181, 67, 149, 202, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[11, 122, 188, 98, 112, 80, 48, 90, 223, 20, 163, 217, 228, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[114, 203, 91, 216, 99, 33, 227, 140, 182, 206, 102, 130, 232, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 123, 241, 150, 115, 223, 82, 227, 127, 36, 16, 1, 29, 16, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[44, 215, 111, 224, 134, 185, 60, 226, 247, 104, 160, 11, 34, 160, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 192, 106, 94, 197, 67, 60, 96, 221, 170, 22, 64, 111, 90, 64, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[17, 132, 39, 179, 180, 160, 91, 200, 168, 164, 222, 132, 89, 134, 128, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[175, 41, 141, 5, 14, 67, 149, 214, 150, 112, 177, 43, 127, 65, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[6, 215, 159, 130, 50, 142, 163, 218, 97, 224, 102, 235, 178, 248, 138, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[68, 108, 59, 21, 249, 146, 102, 135, 210, 196, 5, 52, 253, 181, 100, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 172, 58, 78, 219, 191, 184, 1, 78, 59, 168, 52, 17, 233, 21, 232, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[26, 186, 71, 20, 149, 125, 48, 13, 14, 84, 146, 8, 179, 26, 219, 16, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 11, 70, 198, 205, 214, 227, 224, 130, 143, 77, 180, 86, 255, 12, 142, 160, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[10, 112, 195, 196, 10, 100, 230, 197, 25, 153, 9, 11, 101, 246, 125, 146, 64, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[104, 103, 165, 168, 103, 241, 3, 178, 255, 250, 90, 113, 251, 160, 231, 182, 128, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 20, 12, 120, 148, 15, 106, 36, 253, 255, 199, 136, 115, 212, 73, 13, 33, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[40, 200, 124, 181, 200, 154, 37, 113, 235, 253, 203, 84, 134, 74, 218, 131, 74, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 151, 212, 223, 25, 214, 5, 118, 115, 55, 233, 241, 77, 62, 236, 137, 32, 228, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[15, 238, 80, 183, 2, 92, 54, 160, 128, 47, 35, 109, 4, 117, 61, 91, 72, 232, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[159, 79, 39, 38, 23, 154, 34, 69, 1, 215, 98, 66, 44, 148, 101, 144, 217, 16, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[6, 57, 23, 135, 124, 236, 5, 86, 178, 18, 105, 214, 149, 189, 203, 247, 168, 122, 160, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[62, 58, 235, 74, 225, 56, 53, 98, 244, 184, 34, 97, 217, 105, 247, 172, 148, 202, 64, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 110, 77, 48, 236, 204, 50, 21, 221, 143, 49, 87, 210, 126, 35, 172, 189, 207, 230, 128, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[24, 79, 3, 233, 63, 249, 244, 218, 167, 151, 237, 110, 56, 237, 100, 191, 106, 31, 1, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[243, 22, 39, 28, 127, 195, 144, 138, 139, 239, 70, 78, 57, 69, 239, 122, 37, 54, 10, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[9, 126, 221, 135, 28, 253, 163, 165, 105, 119, 88, 191, 14, 60, 187, 90, 197, 116, 28, 100, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[94, 244, 167, 71, 33, 232, 100, 118, 30, 169, 119, 118, 142, 95, 81, 139, 182, 137, 27, 232, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 181, 142, 136, 199, 83, 19, 236, 157, 50, 158, 170, 161, 143, 185, 47, 117, 33, 91, 23, 16, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[37, 23, 145, 87, 201, 62, 199, 62, 35, 250, 50, 170, 79, 157, 59, 218, 147, 77, 142, 230, 160, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 114, 235, 173, 109, 220, 115, 200, 109, 103, 197, 250, 167, 28, 36, 86, 137, 193, 7, 149, 2, 64, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[14, 125, 52, 198, 74, 156, 133, 212, 70, 13, 187, 202, 135, 25, 107, 97, 97, 138, 75, 210, 22, 128, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[144, 228, 15, 190, 234, 29, 58, 74, 188, 137, 85, 233, 70, 254, 49, 205, 207, 102, 246, 52, 225, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[5, 168, 232, 157, 117, 37, 36, 70, 235, 93, 93, 91, 28, 197, 237, 242, 10, 26, 5, 158, 16, 202, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[56, 153, 22, 38, 147, 115, 106, 197, 49, 165, 165, 143, 31, 187, 75, 116, 101, 4, 56, 44, 167, 228, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 53, 250, 221, 129, 194, 130, 43, 179, 240, 120, 119, 151, 61, 80, 242, 139, 242, 42, 49, 190, 142, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[22, 27, 204, 167, 17, 153, 21, 181, 7, 100, 180, 171, 232, 101, 41, 121, 119, 117, 165, 241, 113, 149, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[221, 21, 254, 134, 175, 250, 217, 18, 73, 239, 14, 183, 19, 243, 158, 190, 170, 152, 123, 110, 111, 210, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[8, 162, 219, 241, 66, 223, 204, 122, 182, 227, 86, 147, 38, 199, 132, 51, 114, 169, 244, 210, 80, 94, 58, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[86, 92, 151, 108, 156, 189, 252, 203, 36, 225, 97, 191, 131, 203, 42, 2, 122, 163, 144, 55, 35, 174, 70, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 95, 157, 234, 62, 31, 107, 223, 239, 112, 205, 209, 123, 37, 239, 164, 24, 202, 99, 162, 39, 100, 206, 193, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[33, 188, 43, 38, 109, 58, 54, 191, 90, 104, 10, 46, 207, 123, 92, 104, 247, 231, 228, 85, 137, 240, 19, 138, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 81, 89, 175, 128, 68, 70, 35, 121, 136, 16, 101, 212, 26, 209, 156, 25, 175, 14, 235, 87, 99, 96, 195, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[13, 45, 128, 219, 2, 170, 189, 98, 191, 80, 163, 250, 73, 12, 48, 25, 0, 214, 149, 49, 105, 225, 199, 161, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[131, 199, 8, 142, 26, 171, 101, 219, 121, 38, 103, 198, 218, 121, 224, 250, 8, 97, 211, 238, 34, 209, 204, 83, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[5, 37, 198, 85, 141, 10, 177, 250, 146, 187, 128, 13, 196, 136, 194, 201, 196, 83, 210, 71, 77, 92, 49, 251, 62, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[51, 121, 191, 87, 130, 106, 243, 201, 187, 83, 0, 137, 173, 87, 155, 225, 171, 70, 54, 201, 5, 153, 243, 208, 114, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 2, 193, 121, 107, 24, 45, 133, 225, 81, 62, 5, 96, 197, 108, 22, 208, 176, 190, 35, 218, 56, 3, 134, 36, 118, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[20, 27, 142, 190, 46, 241, 199, 58, 205, 44, 108, 53, 199, 182, 56, 228, 38, 231, 109, 102, 134, 48, 35, 61, 108, 161, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[201, 19, 147, 109, 213, 113, 200, 76, 3, 188, 58, 25, 205, 30, 56, 233, 133, 10, 70, 1, 61, 225, 96, 102, 62, 74, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[7, 218, 195, 194, 74, 86, 113, 210, 248, 37, 90, 69, 2, 3, 46, 57, 31, 50, 102, 188, 12, 106, 205, 195, 254, 110, 228, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[78, 139, 165, 150, 231, 96, 114, 61, 177, 117, 134, 178, 20, 31, 206, 59, 55, 248, 3, 88, 124, 44, 9, 167, 240, 84, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 17, 116, 119, 229, 9, 196, 118, 104, 238, 151, 66, 244, 201, 62, 14, 80, 47, 176, 33, 116, 217, 184, 96, 143, 99, 81, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[30, 174, 140, 174, 242, 97, 172, 160, 25, 81, 232, 157, 143, 220, 108, 143, 33, 220, 225, 78, 144, 129, 51, 197, 153, 225, 42, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 50, 209, 126, 213, 119, 208, 190, 64, 253, 51, 22, 39, 158, 156, 61, 151, 82, 160, 205, 17, 165, 12, 5, 184, 2, 203, 170, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[11, 252, 46, 244, 86, 174, 39, 110, 137, 227, 254, 221, 140, 50, 26, 103, 233, 58, 72, 2, 176, 114, 120, 57, 48, 27, 244, 166, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[119, 217, 213, 139, 98, 205, 138, 81, 98, 231, 244, 167, 121, 245, 8, 15, 28, 70, 208, 26, 228, 120, 178, 59, 225, 23, 142, 129, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 174, 130, 87, 113, 220, 7, 103, 45, 221, 15, 142, 138, 195, 146, 80, 151, 26, 196, 33, 12, 236, 182, 246, 86, 202, 235, 145, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[46, 209, 23, 106, 114, 152, 74, 7, 202, 162, 155, 145, 107, 163, 183, 37, 231, 11, 169, 74, 129, 63, 37, 159, 99, 237, 51, 170, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 212, 42, 234, 40, 121, 242, 228, 77, 234, 90, 19, 174, 52, 101, 39, 123, 6, 116, 156, 233, 12, 119, 120, 57, 231, 68, 4, 167, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[18, 73, 173, 37, 148, 195, 124, 235, 11, 39, 132, 196, 206, 11, 243, 138, 206, 64, 142, 33, 26, 124, 170, 178, 67, 8, 168, 46, 143, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[182, 224, 195, 119, 207, 162, 225, 46, 111, 139, 47, 176, 12, 119, 131, 108, 14, 133, 141, 75, 8, 222, 170, 246, 158, 86, 145, 209, 150, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[7, 36, 199, 162, 174, 28, 92, 203, 208, 91, 111, 220, 224, 124, 171, 34, 56, 145, 55, 132, 238, 88, 178, 173, 162, 47, 97, 178, 47, 226, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[71, 111, 204, 90, 205, 27, 159, 246, 35, 146, 94, 160, 196, 222, 175, 86, 53, 172, 43, 49, 79, 118, 250, 200, 85, 217, 208, 245, 222, 214, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 202, 93, 251, 140, 3, 20, 63, 157, 99, 183, 178, 71, 176, 178, 217, 94, 24, 185, 175, 237, 26, 165, 203, 211, 90, 130, 41, 154, 180, 97, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[27, 231, 171, 211, 120, 30, 202, 124, 37, 229, 44, 246, 204, 230, 252, 125, 172, 247, 64, 223, 67, 10, 121, 246, 65, 137, 21, 160, 11, 11, 202, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 23, 12, 182, 66, 177, 51, 232, 217, 122, 243, 193, 164, 1, 5, 220, 232, 193, 168, 136, 184, 158, 104, 195, 158, 143, 90, 216, 64, 110, 117, 228, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[10, 230, 127, 30, 154, 236, 7, 24, 126, 205, 133, 144, 104, 10, 58, 161, 23, 144, 149, 87, 54, 48, 23, 164, 49, 153, 140, 114, 132, 80, 154, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[109, 0, 247, 50, 13, 56, 70, 244, 244, 7, 55, 164, 16, 102, 74, 74, 235, 165, 213, 104, 29, 224, 236, 105, 239, 255, 124, 121, 43, 38, 13, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 66, 9, 167, 244, 132, 50, 197, 145, 136, 72, 44, 104, 163, 254, 230, 237, 52, 122, 86, 17, 42, 201, 60, 35, 95, 250, 220, 187, 175, 124, 130, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[42, 148, 96, 143, 141, 41, 251, 183, 175, 82, 209, 188, 22, 103, 245, 5, 68, 12, 199, 92, 171, 171, 220, 89, 97, 191, 204, 159, 84, 218, 221, 26, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 169, 203, 197, 155, 131, 163, 213, 44, 217, 60, 49, 88, 224, 15, 146, 52, 168, 127, 201, 158, 180, 182, 155, 125, 209, 125, 254, 57, 80, 140, 163, 6, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[16, 161, 245, 184, 19, 36, 102, 83, 192, 124, 89, 237, 120, 192, 155, 182, 14, 148, 253, 224, 51, 15, 34, 18, 234, 46, 235, 238, 61, 37, 126, 94, 65, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[166, 83, 153, 48, 191, 107, 255, 69, 132, 219, 131, 70, 183, 134, 21, 28, 145, 209, 234, 193, 254, 151, 84, 189, 37, 213, 55, 78, 99, 118, 239, 174, 138, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[6, 127, 67, 251, 231, 122, 55, 248, 183, 48, 147, 32, 195, 43, 60, 211, 29, 178, 51, 43, 147, 241, 233, 79, 99, 122, 84, 41, 15, 226, 165, 92, 209, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[64, 248, 167, 215, 10, 198, 47, 183, 39, 229, 191, 71, 159, 176, 96, 63, 40, 245, 255, 179, 199, 115, 29, 25, 226, 199, 73, 154, 158, 218, 117, 160, 45, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 137, 182, 142, 102, 107, 189, 221, 39, 142, 249, 120, 204, 60, 227, 194, 119, 153, 155, 253, 5, 202, 127, 35, 2, 219, 200, 224, 10, 52, 136, 152, 65, 203, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[25, 97, 33, 144, 0, 53, 106, 163, 139, 149, 190, 183, 250, 96, 229, 152, 172, 0, 23, 226, 57, 232, 247, 94, 28, 149, 216, 192, 102, 13, 85, 242, 145, 238, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[253, 203, 79, 160, 2, 22, 42, 99, 115, 217, 115, 47, 199, 200, 247, 246, 184, 0, 238, 214, 67, 25, 169, 173, 29, 218, 119, 131, 252, 133, 91, 121, 179, 82, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[9, 233, 241, 28, 64, 20, 221, 167, 226, 134, 126, 127, 221, 205, 217, 175, 163, 48, 9, 84, 94, 159, 0, 160, 195, 42, 136, 171, 39, 221, 53, 146, 193, 1, 54, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[99, 35, 107, 26, 128, 208, 168, 142, 217, 64, 240, 254, 170, 10, 128, 220, 95, 224, 93, 75, 178, 54, 6, 71, 159, 169, 86, 175, 142, 164, 23, 187, 138, 12, 33, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 223, 98, 47, 9, 8, 38, 149, 148, 124, 137, 105, 242, 164, 105, 8, 155, 190, 195, 164, 244, 246, 28, 62, 204, 60, 157, 98, 219, 146, 104, 237, 83, 100, 121, 74, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[38, 185, 213, 214, 90, 81, 129, 215, 204, 221, 94, 35, 122, 108, 26, 86, 21, 115, 164, 113, 145, 157, 26, 115, 250, 94, 37, 220, 147, 184, 25, 69, 65, 236, 188, 228, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 131, 66, 90, 95, 135, 47, 18, 110, 0, 165, 173, 98, 200, 57, 7, 92, 214, 132, 108, 111, 176, 35, 8, 135, 199, 173, 122, 157, 197, 48, 252, 180, 147, 63, 96, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[15, 32, 151, 135, 187, 71, 214, 184, 76, 6, 120, 197, 219, 210, 58, 73, 160, 97, 44, 60, 92, 225, 94, 85, 77, 204, 198, 202, 41, 179, 233, 223, 13, 192, 121, 201, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[151, 69, 235, 77, 80, 206, 99, 50, 248, 64, 183, 186, 150, 54, 70, 224, 67, 203, 186, 91, 160, 205, 175, 85, 9, 255, 195, 229, 161, 7, 34, 182, 137, 132, 193, 218, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[5, 232, 187, 49, 5, 40, 15, 223, 253, 178, 135, 45, 73, 222, 30, 196, 194, 165, 245, 71, 148, 72, 8, 217, 82, 99, 253, 166, 248, 74, 71, 91, 33, 95, 47, 146, 138, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[59, 23, 79, 234, 51, 144, 158, 191, 232, 249, 71, 196, 226, 173, 51, 175, 154, 123, 148, 203, 202, 208, 88, 125, 55, 231, 232, 133, 178, 230, 201, 143, 77, 183, 219, 185, 102, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 78, 233, 31, 38, 3, 166, 51, 127, 25, 188, 205, 176, 218, 196, 4, 220, 8, 211, 207, 245, 236, 35, 116, 228, 47, 15, 21, 56, 253, 3, 223, 153, 9, 46, 149, 62, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[23, 21, 27, 55, 124, 36, 126, 2, 247, 1, 96, 8, 232, 139, 168, 48, 152, 88, 70, 31, 155, 57, 98, 144, 233, 214, 150, 212, 57, 226, 38, 187, 250, 91, 209, 212, 108, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[230, 211, 16, 42, 217, 108, 236, 29, 166, 13, 192, 89, 21, 116, 145, 229, 243, 114, 189, 60, 16, 61, 217, 169, 34, 97, 228, 74, 66, 213, 131, 87, 199, 150, 50, 76, 56, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[9, 4, 62, 161, 172, 126, 65, 57, 40, 124, 137, 131, 122, 214, 141, 178, 251, 130, 123, 100, 88, 162, 106, 128, 155, 87, 210, 234, 230, 156, 87, 33, 109, 203, 221, 246, 250, 51, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[90, 42, 114, 80, 188, 238, 140, 59, 148, 221, 95, 34, 204, 97, 136, 253, 211, 24, 209, 235, 118, 88, 41, 6, 17, 110, 61, 45, 2, 27, 103, 78, 73, 246, 171, 165, 198, 7, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 133, 168, 119, 39, 97, 81, 122, 83, 208, 165, 183, 91, 251, 207, 89, 234, 62, 248, 51, 50, 159, 113, 154, 60, 174, 78, 99, 194, 21, 18, 9, 14, 227, 162, 180, 121, 188, 70, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[35, 56, 148, 167, 137, 205, 46, 199, 70, 38, 121, 41, 151, 214, 25, 131, 38, 117, 177, 255, 250, 58, 112, 6, 94, 207, 15, 229, 148, 210, 180, 90, 148, 228, 91, 12, 193, 90, 194, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 96, 53, 206, 139, 98, 3, 211, 200, 189, 128, 187, 159, 238, 92, 255, 31, 128, 152, 243, 255, 198, 72, 96, 63, 180, 22, 158, 247, 208, 59, 11, 137, 208, 235, 142, 127, 141, 139, 150, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[13, 194, 26, 17, 113, 212, 38, 69, 215, 103, 7, 84, 63, 79, 161, 247, 59, 5, 249, 135, 253, 190, 211, 194, 125, 8, 226, 53, 174, 34, 78, 115, 98, 41, 51, 144, 251, 135, 115, 225, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[137, 149, 4, 174, 114, 73, 126, 186, 106, 6, 73, 74, 121, 28, 83, 168, 78, 59, 191, 79, 233, 116, 69, 152, 226, 88, 214, 24, 205, 87, 16, 129, 213, 156, 3, 169, 211, 74, 134, 202, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[5, 95, 210, 46, 208, 118, 222, 243, 72, 36, 62, 220, 232, 187, 27, 68, 147, 14, 85, 121, 31, 30, 138, 183, 248, 215, 120, 92, 248, 5, 102, 165, 18, 88, 24, 36, 162, 64, 233, 67, 228, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[53, 190, 53, 212, 36, 164, 181, 128, 209, 106, 116, 161, 23, 79, 16, 173, 190, 143, 86, 187, 55, 49, 107, 47, 184, 106, 179, 161, 176, 54, 2, 114, 183, 112, 241, 110, 86, 137, 28, 166, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 25, 110, 26, 73, 110, 111, 23, 8, 46, 40, 142, 74, 233, 22, 166, 201, 113, 153, 99, 80, 39, 238, 47, 221, 52, 43, 4, 80, 226, 28, 24, 123, 42, 105, 110, 79, 97, 91, 30, 133, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[20, 254, 77, 6, 222, 80, 86, 230, 81, 205, 149, 142, 237, 26, 226, 131, 222, 111, 253, 225, 33, 143, 77, 222, 164, 9, 174, 43, 40, 213, 24, 244, 207, 168, 30, 79, 25, 205, 143, 49, 50, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[209, 239, 2, 68, 175, 35, 100, 255, 50, 7, 215, 149, 67, 12, 217, 38, 176, 95, 234, 203, 79, 153, 10, 178, 104, 96, 205, 175, 152, 82, 249, 144, 28, 145, 47, 23, 2, 7, 151, 235, 250, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[8, 51, 86, 22, 174, 215, 97, 241, 247, 244, 78, 107, 212, 158, 128, 123, 130, 227, 191, 43, 241, 27, 250, 106, 248, 19, 200, 8, 219, 243, 61, 191, 161, 29, 171, 214, 230, 20, 75, 239, 55, 198, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[82, 1, 92, 226, 212, 105, 211, 115, 175, 139, 16, 54, 78, 49, 4, 211, 28, 229, 119, 183, 107, 23, 200, 45, 176, 197, 208, 88, 151, 128, 105, 124, 75, 40, 182, 100, 252, 202, 247, 88, 45, 193, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 52, 13, 160, 220, 76, 34, 66, 132, 219, 110, 162, 31, 13, 234, 48, 63, 32, 246, 173, 42, 46, 237, 209, 200, 231, 186, 35, 117, 235, 4, 30, 218, 239, 151, 31, 241, 223, 237, 169, 113, 201, 138, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[32, 8, 136, 72, 154, 249, 86, 153, 48, 146, 82, 85, 54, 139, 37, 226, 119, 73, 162, 195, 165, 213, 74, 49, 217, 13, 69, 98, 155, 46, 41, 52, 141, 91, 231, 63, 114, 191, 72, 158, 113, 223, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 64, 85, 82, 214, 13, 189, 97, 251, 229, 183, 55, 84, 33, 111, 122, 216, 168, 224, 91, 164, 122, 84, 229, 242, 122, 132, 181, 218, 15, 205, 156, 13, 133, 151, 8, 122, 123, 120, 214, 48, 114, 185, 232, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[12, 131, 85, 60, 92, 137, 101, 211, 214, 249, 40, 41, 73, 78, 90, 204, 118, 152, 195, 148, 108, 199, 80, 251, 120, 201, 47, 26, 132, 158, 8, 24, 135, 55, 230, 84, 200, 210, 184, 93, 228, 123, 67, 16, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[125, 33, 84, 91, 157, 93, 250, 70, 101, 187, 145, 156, 221, 15, 139, 252, 161, 247, 163, 204, 63, 201, 41, 210, 183, 219, 215, 9, 46, 44, 80, 245, 72, 46, 255, 79, 216, 59, 51, 170, 236, 208, 158, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 227, 77, 75, 148, 37, 171, 198, 191, 249, 83, 176, 32, 162, 155, 119, 222, 83, 172, 101, 250, 125, 219, 162, 59, 46, 150, 102, 91, 205, 187, 41, 148, 209, 213, 249, 30, 114, 80, 4, 173, 64, 38, 50, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[48, 225, 4, 243, 201, 120, 181, 195, 127, 189, 68, 225, 70, 90, 18, 174, 175, 68, 187, 251, 200, 234, 148, 86, 79, 209, 223, 255, 150, 9, 79, 159, 208, 50, 91, 187, 48, 119, 32, 46, 196, 129, 125, 246, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 232, 202, 49, 133, 222, 183, 25, 162, 253, 100, 176, 204, 191, 132, 186, 210, 216, 175, 87, 213, 217, 41, 203, 95, 30, 50, 191, 251, 220, 93, 28, 62, 33, 247, 149, 79, 228, 167, 65, 211, 173, 14, 235, 161, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[19, 23, 229, 239, 58, 179, 39, 0, 93, 229, 238, 231, 255, 123, 47, 76, 60, 118, 217, 110, 90, 123, 161, 241, 183, 45, 251, 127, 214, 155, 163, 26, 109, 83, 171, 213, 30, 238, 136, 146, 68, 194, 149, 52, 74, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[190, 238, 251, 88, 74, 255, 134, 3, 170, 251, 85, 15, 250, 207, 216, 250, 92, 164, 126, 79, 136, 212, 83, 113, 39, 203, 210, 254, 98, 20, 95, 8, 69, 68, 182, 83, 53, 81, 85, 182, 175, 153, 212, 10, 228, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    ];

version(ShowEnumDecBytes)
unittest
{
    static assert(pow10_512[0 + 20]   == uint512("100000000000000000000")); // 20
    static assert(pow10_512[1 + 20]   == uint512("1000000000000000000000"));
    static assert(pow10_512[2 + 20]   == uint512("10000000000000000000000"));
    static assert(pow10_512[3 + 20]   == uint512("100000000000000000000000"));
    static assert(pow10_512[4 + 20]   == uint512("1000000000000000000000000"));
    static assert(pow10_512[5 + 20]   == uint512("10000000000000000000000000"));
    static assert(pow10_512[6 + 20]   == uint512("100000000000000000000000000"));
    static assert(pow10_512[7 + 20]   == uint512("1000000000000000000000000000"));
    static assert(pow10_512[8 + 20]   == uint512("10000000000000000000000000000"));
    static assert(pow10_512[9 + 20]   == uint512("100000000000000000000000000000"));
    static assert(pow10_512[10 + 20]  == uint512("1000000000000000000000000000000"));
    static assert(pow10_512[11 + 20]  == uint512("10000000000000000000000000000000"));
    static assert(pow10_512[12 + 20]  == uint512("100000000000000000000000000000000"));
    static assert(pow10_512[13 + 20]  == uint512("1000000000000000000000000000000000"));
    static assert(pow10_512[14 + 20]  == uint512("10000000000000000000000000000000000"));
    static assert(pow10_512[15 + 20]  == uint512("100000000000000000000000000000000000"));
    static assert(pow10_512[16 + 20]  == uint512("1000000000000000000000000000000000000"));
    static assert(pow10_512[17 + 20]  == uint512("10000000000000000000000000000000000000"));
    static assert(pow10_512[18 + 20]  == uint512("100000000000000000000000000000000000000"));
    static assert(pow10_512[19 + 20]  == uint512("1000000000000000000000000000000000000000"));
    static assert(pow10_512[20 + 20]  == uint512("10000000000000000000000000000000000000000"));
    static assert(pow10_512[21 + 20]  == uint512("100000000000000000000000000000000000000000"));
    static assert(pow10_512[22 + 20]  == uint512("1000000000000000000000000000000000000000000"));
    static assert(pow10_512[23 + 20]  == uint512("10000000000000000000000000000000000000000000"));
    static assert(pow10_512[24 + 20]  == uint512("100000000000000000000000000000000000000000000"));
    static assert(pow10_512[25 + 20]  == uint512("1000000000000000000000000000000000000000000000"));
    static assert(pow10_512[26 + 20]  == uint512("10000000000000000000000000000000000000000000000"));
    static assert(pow10_512[27 + 20]  == uint512("100000000000000000000000000000000000000000000000"));
    static assert(pow10_512[28 + 20]  == uint512("1000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[29 + 20]  == uint512("10000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[30 + 20]  == uint512("100000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[31 + 20]  == uint512("1000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[32 + 20]  == uint512("10000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[33 + 20]  == uint512("100000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[34 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[35 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[36 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[37 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[38 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[39 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[40 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[41 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[42 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[43 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[44 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[45 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[46 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[47 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[48 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[49 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[50 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[51 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[52 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[53 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[54 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[55 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[56 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[57 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[58 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[59 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[60 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[61 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[62 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[63 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[64 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[65 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[66 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[67 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[68 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[69 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[70 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[71 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[72 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[73 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[74 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[75 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[76 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[77 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[78 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[79 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[80 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[81 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[82 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[83 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[84 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[85 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[86 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[87 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[88 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[89 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[90 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[91 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[92 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[93 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[94 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[95 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[96 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[97 + 20]  == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[98 + 20]  == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[99 + 20]  == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[100 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[101 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[102 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[103 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[104 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[105 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[106 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[107 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[108 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[109 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[110 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[111 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[112 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[113 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[114 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[115 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[116 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[117 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[118 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[119 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[120 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[121 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[122 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[123 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[124 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[125 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[126 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[127 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[128 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[129 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[130 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[131 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[132 + 20] == uint512("100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[133 + 20] == uint512("1000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10_512[134 + 20] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
}

template pow10(T)
{
    alias UT = Unqual!T;

    static if (is(UT == uint))
        alias pow10 = pow10_32;
    else static if (is(UT == ulong))
        alias pow10 = pow10_64;
    else static if (is(UT == uint128))
        alias pow10 = pow10_128;
    else static if (is(UT == uint256))
        alias pow10 = pow10_256;
    else static if (is(UT == uint512))
        alias pow10 = pow10_512;
    else static if (is(UT == ushort))
        alias pow10 = pow10_16;
    else static if (is(UT == ubyte))
        alias pow10 = pow10_8;
    else
        static assert(0);
}

int pow10Index(T)(int index)
{
    alias table = pow10!T;
    return index < 0 ? 0 : (index >= table.length ? table.length - 1 : index);
}

static immutable ubyte[3] pow10RoundEven_8 = [
    5U,
    50U,
    100U,
    ];

static immutable ushort[5] pow10RoundEven_16 = [
    5U,
    50U,
    500U,
    5000U,
    50000U,
    ];

//pragma(msg, uint.max); // 4294967295u
static immutable uint[10] pow10RoundEven_32 = [
    5U,
    50U,
    500U,
    5000U,
    50000U,
    500000U,
    5000000U,
    50000000U,
    500000000U,
    1000000000U,
    ];

//pragma(msg, ulong.max); // 18446744073709551615LU
static immutable ulong[20] pow10RoundEven_64 = [
    5UL,
    50UL,
    500UL,
    5000UL,
    50000UL,
    500000UL,
    5000000UL,
    50000000UL,
    500000000UL,
    5000000000UL,
    50000000000UL,
    500000000000UL,
    5000000000000UL,
    50000000000000UL,
    500000000000000UL,
    5000000000000000UL,
    50000000000000000UL,
    500000000000000000UL,
    5000000000000000000UL,
    10000000000000000000UL,
    ];

static immutable uint128[39] pow10RoundEven_128 = [
    uint128(5UL), // 0
    uint128(50UL),
    uint128(500UL),
    uint128(5000UL),
    uint128(50000UL), // 4
    uint128(500000UL),
    uint128(5000000UL),
    uint128(50000000UL),
    uint128(500000000UL),
    uint128(5000000000UL), // 9
    uint128(50000000000UL),
    uint128(500000000000UL),
    uint128(5000000000000UL),
    uint128(50000000000000UL),
    uint128(500000000000000UL), // 14
    uint128(5000000000000000UL),
    uint128(50000000000000000UL),
    uint128(500000000000000000UL),
    uint128(5000000000000000000UL),
    uint128(cast(const(ubyte)[])[2, 181, 227, 175, 22, 177, 136, 0, 0]),         // uint128("50000000000000000000"), // 19
    uint128(cast(const(ubyte)[])[27, 26, 228, 214, 226, 239, 80, 0, 0]),         // uint128("500000000000000000000"),
    uint128(cast(const(ubyte)[])[1, 15, 12, 240, 100, 221, 89, 32, 0, 0]),          // uint128("5000000000000000000000"),
    uint128(cast(const(ubyte)[])[10, 150, 129, 99, 240, 165, 123, 64, 0, 0]),       // uint128("50000000000000000000000"),
    uint128(cast(const(ubyte)[])[105, 225, 13, 231, 102, 118, 208, 128, 0, 0]),     // uint128("500000000000000000000000"),
    uint128(cast(const(ubyte)[])[4, 34, 202, 139, 10, 0, 164, 37, 0, 0, 0]),           // uint128("5000000000000000000000000"),
    uint128(cast(const(ubyte)[])[41, 91, 233, 110, 100, 6, 105, 114, 0, 0, 0]),        // uint128("50000000000000000000000000"),
    uint128(cast(const(ubyte)[])[1, 157, 151, 30, 79, 232, 64, 30, 116, 0, 0, 0]),        // uint128("500000000000000000000000000"),
    uint128(cast(const(ubyte)[])[16, 39, 231, 47, 31, 18, 129, 48, 136, 0, 0, 0]),        // uint128("5000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[161, 143, 7, 215, 54, 185, 11, 229, 80, 0, 0, 0]),       // uint128("50000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[6, 79, 150, 78, 104, 35, 58, 118, 245, 32, 0, 0, 0]),       // uint128("500000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[63, 27, 223, 16, 17, 96, 72, 165, 147, 64, 0, 0, 0]),       // uint128("5000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[2, 119, 22, 182, 160, 173, 194, 214, 119, 192, 128, 0, 0, 0]), // uint128("50000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[24, 166, 227, 34, 70, 201, 156, 96, 173, 133, 0, 0, 0, 0]),    // uint128("500000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[246, 132, 223, 86, 195, 224, 27, 198, 199, 50, 0, 0, 0, 0]),   // uint128("5000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[9, 161, 48, 185, 99, 166, 193, 21, 195, 199, 244, 0, 0, 0, 0]),   // uint128("50000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[96, 75, 231, 61, 228, 131, 138, 217, 165, 207, 136, 0, 0, 0, 0]), // uint128("500000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[3, 194, 247, 8, 106, 237, 35, 108, 128, 122, 27, 80, 0, 0, 0, 0]),   // uint128("5000000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[37, 157, 166, 84, 45, 67, 98, 61, 4, 197, 17, 32, 0, 0, 0, 0]),      // uint128("50000000000000000000000000000000000000"),
    uint128(cast(const(ubyte)[])[75, 59, 76, 168, 90, 134, 196, 122, 9, 138, 34, 64, 0, 0, 0, 0]),    // uint128("100000000000000000000000000000000000000"),
    ];

version(ShowEnumDecBytes)
unittest
{
    static assert(pow10RoundEven_128[0 + 19]  == uint128("50000000000000000000")); // 19
    static assert(pow10RoundEven_128[1 + 19]  == uint128("500000000000000000000"));
    static assert(pow10RoundEven_128[2 + 19]  == uint128("5000000000000000000000"));
    static assert(pow10RoundEven_128[3 + 19]  == uint128("50000000000000000000000"));
    static assert(pow10RoundEven_128[4 + 19]  == uint128("500000000000000000000000"));
    static assert(pow10RoundEven_128[5 + 19]  == uint128("5000000000000000000000000"));
    static assert(pow10RoundEven_128[6 + 19]  == uint128("50000000000000000000000000"));
    static assert(pow10RoundEven_128[7 + 19]  == uint128("500000000000000000000000000"));
    static assert(pow10RoundEven_128[8 + 19]  == uint128("5000000000000000000000000000"));
    static assert(pow10RoundEven_128[9 + 19]  == uint128("50000000000000000000000000000"));
    static assert(pow10RoundEven_128[10 + 19] == uint128("500000000000000000000000000000"));
    static assert(pow10RoundEven_128[11 + 19] == uint128("5000000000000000000000000000000"));
    static assert(pow10RoundEven_128[12 + 19] == uint128("50000000000000000000000000000000"));
    static assert(pow10RoundEven_128[13 + 19] == uint128("500000000000000000000000000000000"));
    static assert(pow10RoundEven_128[14 + 19] == uint128("5000000000000000000000000000000000"));
    static assert(pow10RoundEven_128[15 + 19] == uint128("50000000000000000000000000000000000"));
    static assert(pow10RoundEven_128[16 + 19] == uint128("500000000000000000000000000000000000"));
    static assert(pow10RoundEven_128[17 + 19] == uint128("5000000000000000000000000000000000000"));
    static assert(pow10RoundEven_128[18 + 19] == uint128("50000000000000000000000000000000000000"));
    static assert(pow10RoundEven_128[19 + 19] == uint128("100000000000000000000000000000000000000"));
}

static immutable uint256[78] pow10RoundEven_256 = [
    uint256(5UL),
    uint256(50UL),
    uint256(500UL),
    uint256(5000UL),
    uint256(50000UL), // 4
    uint256(500000UL),
    uint256(5000000UL),
    uint256(50000000UL),
    uint256(500000000UL),
    uint256(5000000000UL), // 9
    uint256(50000000000UL),
    uint256(500000000000UL),
    uint256(5000000000000UL),
    uint256(50000000000000UL),
    uint256(500000000000000UL), // 14
    uint256(5000000000000000UL),
    uint256(50000000000000000UL),
    uint256(500000000000000000UL),
    uint256(5000000000000000000UL),
    uint256(cast(const(ubyte)[])[2, 181, 227, 175, 22, 177, 136, 0, 0]), // uint256("50000000000000000000"), // 19
    uint256(cast(const(ubyte)[])[27, 26, 228, 214, 226, 239, 80, 0, 0]), // uint256("500000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 15, 12, 240, 100, 221, 89, 32, 0, 0]), // uint256("5000000000000000000000"),
    uint256(cast(const(ubyte)[])[10, 150, 129, 99, 240, 165, 123, 64, 0, 0]), // uint256("50000000000000000000000"),
    uint256(cast(const(ubyte)[])[105, 225, 13, 231, 102, 118, 208, 128, 0, 0]), // uint256("500000000000000000000000"),
    uint256(cast(const(ubyte)[])[4, 34, 202, 139, 10, 0, 164, 37, 0, 0, 0]), // uint256("5000000000000000000000000"),
    uint256(cast(const(ubyte)[])[41, 91, 233, 110, 100, 6, 105, 114, 0, 0, 0]), // uint256("50000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 157, 151, 30, 79, 232, 64, 30, 116, 0, 0, 0]), // uint256("500000000000000000000000000"),
    uint256(cast(const(ubyte)[])[16, 39, 231, 47, 31, 18, 129, 48, 136, 0, 0, 0]), // uint256("5000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[161, 143, 7, 215, 54, 185, 11, 229, 80, 0, 0, 0]), // uint256("50000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[6, 79, 150, 78, 104, 35, 58, 118, 245, 32, 0, 0, 0]), // uint256("500000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[63, 27, 223, 16, 17, 96, 72, 165, 147, 64, 0, 0, 0]), // uint256("5000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 119, 22, 182, 160, 173, 194, 214, 119, 192, 128, 0, 0, 0]), // uint256("50000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[24, 166, 227, 34, 70, 201, 156, 96, 173, 133, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[246, 132, 223, 86, 195, 224, 27, 198, 199, 50, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[9, 161, 48, 185, 99, 166, 193, 21, 195, 199, 244, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[96, 75, 231, 61, 228, 131, 138, 217, 165, 207, 136, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[3, 194, 247, 8, 106, 237, 35, 108, 128, 122, 27, 80, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[37, 157, 166, 84, 45, 67, 98, 61, 4, 197, 17, 32, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 120, 40, 127, 73, 196, 161, 214, 98, 47, 178, 171, 64, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[14, 177, 148, 248, 225, 174, 82, 95, 213, 220, 250, 176, 128, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[146, 239, 209, 184, 208, 207, 55, 190, 90, 161, 202, 229, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[5, 189, 94, 49, 56, 40, 24, 45, 111, 138, 81, 236, 242, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[57, 101, 173, 236, 49, 144, 241, 198, 91, 103, 51, 65, 116, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 61, 248, 203, 57, 239, 169, 113, 191, 146, 8, 0, 142, 136, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[22, 107, 183, 240, 67, 92, 158, 113, 123, 180, 80, 5, 145, 80, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[224, 53, 47, 98, 161, 158, 48, 110, 213, 11, 32, 55, 173, 32, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[8, 194, 19, 217, 218, 80, 45, 228, 84, 82, 111, 66, 44, 195, 64, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[87, 148, 198, 130, 135, 33, 202, 235, 75, 56, 88, 149, 191, 160, 128, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[3, 107, 207, 193, 25, 71, 81, 237, 48, 240, 51, 117, 217, 124, 69, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[34, 54, 29, 138, 252, 201, 51, 67, 233, 98, 2, 154, 126, 218, 178, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 86, 29, 39, 109, 223, 220, 0, 167, 29, 212, 26, 8, 244, 138, 244, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[13, 93, 35, 138, 74, 190, 152, 6, 135, 42, 73, 4, 89, 141, 109, 136, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[133, 163, 99, 102, 235, 113, 240, 65, 71, 166, 218, 43, 127, 134, 71, 80, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[5, 56, 97, 226, 5, 50, 115, 98, 140, 204, 132, 133, 178, 251, 62, 201, 32, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[52, 51, 210, 212, 51, 248, 129, 217, 127, 253, 45, 56, 253, 208, 115, 219, 64, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 10, 6, 60, 74, 7, 181, 18, 126, 255, 227, 196, 57, 234, 36, 134, 144, 128, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[20, 100, 62, 90, 228, 77, 18, 184, 245, 254, 229, 170, 67, 37, 109, 65, 165, 0, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[203, 234, 111, 140, 235, 2, 187, 57, 155, 244, 248, 166, 159, 118, 68, 144, 114, 0, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[7, 247, 40, 91, 129, 46, 27, 80, 64, 23, 145, 182, 130, 58, 158, 173, 164, 116, 0, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[79, 167, 147, 147, 11, 205, 17, 34, 128, 235, 177, 33, 22, 74, 50, 200, 108, 136, 0, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[3, 28, 139, 195, 190, 118, 2, 171, 89, 9, 52, 235, 74, 222, 229, 251, 212, 61, 80, 0, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[31, 29, 117, 165, 112, 156, 26, 177, 122, 92, 17, 48, 236, 180, 251, 214, 74, 101, 32, 0, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 55, 38, 152, 118, 102, 25, 10, 238, 199, 152, 171, 233, 63, 17, 214, 94, 231, 243, 64, 0, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[12, 39, 129, 244, 159, 252, 250, 109, 83, 203, 246, 183, 28, 118, 178, 95, 181, 15, 128, 128, 0, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[121, 139, 19, 142, 63, 225, 200, 69, 69, 247, 163, 39, 28, 162, 247, 189, 18, 155, 5, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[4, 191, 110, 195, 142, 126, 209, 210, 180, 187, 172, 95, 135, 30, 93, 173, 98, 186, 14, 50, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[47, 122, 83, 163, 144, 244, 50, 59, 15, 84, 187, 187, 71, 47, 168, 197, 219, 68, 141, 244, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 218, 199, 68, 99, 169, 137, 246, 78, 153, 79, 85, 80, 199, 220, 151, 186, 144, 173, 139, 136, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[18, 139, 200, 171, 228, 159, 99, 159, 17, 253, 25, 85, 39, 206, 157, 237, 73, 166, 199, 115, 80, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[185, 117, 214, 182, 238, 57, 228, 54, 179, 226, 253, 83, 142, 18, 43, 68, 224, 131, 202, 129, 32, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[7, 62, 154, 99, 37, 78, 66, 234, 35, 6, 221, 229, 67, 140, 181, 176, 176, 197, 37, 233, 11, 64, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[72, 114, 7, 223, 117, 14, 157, 37, 94, 68, 170, 244, 163, 127, 24, 230, 231, 179, 123, 26, 112, 128, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[2, 212, 116, 78, 186, 146, 146, 35, 117, 174, 174, 173, 142, 98, 246, 249, 5, 13, 2, 207, 8, 101, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[28, 76, 139, 19, 73, 185, 181, 98, 152, 210, 210, 199, 143, 221, 165, 186, 50, 130, 28, 22, 83, 242, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[1, 26, 253, 110, 192, 225, 65, 21, 217, 248, 60, 59, 203, 158, 168, 121, 69, 249, 21, 24, 223, 71, 116, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("500000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[11, 13, 230, 83, 136, 204, 138, 218, 131, 178, 90, 85, 244, 50, 148, 188, 187, 186, 210, 248, 184, 202, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("5000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[110, 138, 255, 67, 87, 253, 108, 137, 36, 247, 135, 91, 137, 249, 207, 95, 85, 76, 61, 183, 55, 233, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("50000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint256(cast(const(ubyte)[])[221, 21, 254, 134, 175, 250, 217, 18, 73, 239, 14, 183, 19, 243, 158, 190, 170, 152, 123, 110, 111, 210, 160, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint256("100000000000000000000000000000000000000000000000000000000000000000000000000000"),
    ];

version(ShowEnumDecBytes)
unittest
{
    static assert(pow10RoundEven_256[0 + 19]  == uint256("50000000000000000000")); // 19
    static assert(pow10RoundEven_256[1 + 19]  == uint256("500000000000000000000"));
    static assert(pow10RoundEven_256[2 + 19]  == uint256("5000000000000000000000"));
    static assert(pow10RoundEven_256[3 + 19]  == uint256("50000000000000000000000"));
    static assert(pow10RoundEven_256[4 + 19]  == uint256("500000000000000000000000"));
    static assert(pow10RoundEven_256[5 + 19]  == uint256("5000000000000000000000000"));
    static assert(pow10RoundEven_256[6 + 19]  == uint256("50000000000000000000000000"));
    static assert(pow10RoundEven_256[7 + 19]  == uint256("500000000000000000000000000"));
    static assert(pow10RoundEven_256[8 + 19]  == uint256("5000000000000000000000000000"));
    static assert(pow10RoundEven_256[9 + 19]  == uint256("50000000000000000000000000000"));
    static assert(pow10RoundEven_256[10 + 19] == uint256("500000000000000000000000000000"));
    static assert(pow10RoundEven_256[11 + 19] == uint256("5000000000000000000000000000000"));
    static assert(pow10RoundEven_256[12 + 19] == uint256("50000000000000000000000000000000"));
    static assert(pow10RoundEven_256[13 + 19] == uint256("500000000000000000000000000000000"));
    static assert(pow10RoundEven_256[14 + 19] == uint256("5000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[15 + 19] == uint256("50000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[16 + 19] == uint256("500000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[17 + 19] == uint256("5000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[18 + 19] == uint256("50000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[19 + 19] == uint256("500000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[20 + 19] == uint256("5000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[21 + 19] == uint256("50000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[22 + 19] == uint256("500000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[23 + 19] == uint256("5000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[24 + 19] == uint256("50000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[25 + 19] == uint256("500000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[26 + 19] == uint256("5000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[27 + 19] == uint256("50000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[28 + 19] == uint256("500000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[29 + 19] == uint256("5000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[30 + 19] == uint256("50000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[31 + 19] == uint256("500000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[32 + 19] == uint256("5000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[33 + 19] == uint256("50000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[34 + 19] == uint256("500000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[35 + 19] == uint256("5000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[36 + 19] == uint256("50000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[37 + 19] == uint256("500000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[38 + 19] == uint256("5000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[39 + 19] == uint256("50000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[40 + 19] == uint256("500000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[41 + 19] == uint256("5000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[42 + 19] == uint256("50000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[43 + 19] == uint256("500000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[44 + 19] == uint256("5000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[45 + 19] == uint256("50000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[46 + 19] == uint256("500000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[47 + 19] == uint256("5000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[48 + 19] == uint256("50000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[49 + 19] == uint256("500000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[50 + 19] == uint256("5000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[51 + 19] == uint256("50000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[52 + 19] == uint256("500000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[53 + 19] == uint256("5000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[54 + 19] == uint256("50000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[55 + 19] == uint256("500000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[56 + 19] == uint256("5000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[57 + 19] == uint256("50000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_256[58 + 19] == uint256("100000000000000000000000000000000000000000000000000000000000000000000000000000"));
}

static immutable uint512[155] pow10RoundEven_512 = [
    uint512(5UL),
    uint512(50UL),
    uint512(500UL),
    uint512(5000UL),
    uint512(50000UL), // 4
    uint512(500000UL),
    uint512(5000000UL),
    uint512(50000000UL),
    uint512(500000000UL),
    uint512(5000000000UL), // 9
    uint512(50000000000UL),
    uint512(500000000000UL),
    uint512(5000000000000UL),
    uint512(50000000000000UL),
    uint512(500000000000000UL), // 14
    uint512(5000000000000000UL),
    uint512(50000000000000000UL),
    uint512(500000000000000000UL),
    uint512(5000000000000000000UL),
    uint512(cast(const(ubyte)[])[2, 181, 227, 175, 22, 177, 136, 0, 0]), // uint512("50000000000000000000"), // 19
    uint512(cast(const(ubyte)[])[27, 26, 228, 214, 226, 239, 80, 0, 0]), // uint512("500000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 15, 12, 240, 100, 221, 89, 32, 0, 0]), // uint512("5000000000000000000000"),
    uint512(cast(const(ubyte)[])[10, 150, 129, 99, 240, 165, 123, 64, 0, 0]), // uint512("50000000000000000000000"),
    uint512(cast(const(ubyte)[])[105, 225, 13, 231, 102, 118, 208, 128, 0, 0]), // uint512("500000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 34, 202, 139, 10, 0, 164, 37, 0, 0, 0]), // uint512("5000000000000000000000000"),
    uint512(cast(const(ubyte)[])[41, 91, 233, 110, 100, 6, 105, 114, 0, 0, 0]), // uint512("50000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 157, 151, 30, 79, 232, 64, 30, 116, 0, 0, 0]), // uint512("500000000000000000000000000"),
    uint512(cast(const(ubyte)[])[16, 39, 231, 47, 31, 18, 129, 48, 136, 0, 0, 0]), // uint512("5000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[161, 143, 7, 215, 54, 185, 11, 229, 80, 0, 0, 0]), // uint512("50000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[6, 79, 150, 78, 104, 35, 58, 118, 245, 32, 0, 0, 0]), // uint512("500000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[63, 27, 223, 16, 17, 96, 72, 165, 147, 64, 0, 0, 0]), // uint512("5000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 119, 22, 182, 160, 173, 194, 214, 119, 192, 128, 0, 0, 0]), // uint512("50000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[24, 166, 227, 34, 70, 201, 156, 96, 173, 133, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[246, 132, 223, 86, 195, 224, 27, 198, 199, 50, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[9, 161, 48, 185, 99, 166, 193, 21, 195, 199, 244, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[96, 75, 231, 61, 228, 131, 138, 217, 165, 207, 136, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 194, 247, 8, 106, 237, 35, 108, 128, 122, 27, 80, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[37, 157, 166, 84, 45, 67, 98, 61, 4, 197, 17, 32, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 120, 40, 127, 73, 196, 161, 214, 98, 47, 178, 171, 64, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[14, 177, 148, 248, 225, 174, 82, 95, 213, 220, 250, 176, 128, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[146, 239, 209, 184, 208, 207, 55, 190, 90, 161, 202, 229, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[5, 189, 94, 49, 56, 40, 24, 45, 111, 138, 81, 236, 242, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[57, 101, 173, 236, 49, 144, 241, 198, 91, 103, 51, 65, 116, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 61, 248, 203, 57, 239, 169, 113, 191, 146, 8, 0, 142, 136, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[22, 107, 183, 240, 67, 92, 158, 113, 123, 180, 80, 5, 145, 80, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[224, 53, 47, 98, 161, 158, 48, 110, 213, 11, 32, 55, 173, 32, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[8, 194, 19, 217, 218, 80, 45, 228, 84, 82, 111, 66, 44, 195, 64, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[87, 148, 198, 130, 135, 33, 202, 235, 75, 56, 88, 149, 191, 160, 128, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 107, 207, 193, 25, 71, 81, 237, 48, 240, 51, 117, 217, 124, 69, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[34, 54, 29, 138, 252, 201, 51, 67, 233, 98, 2, 154, 126, 218, 178, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 86, 29, 39, 109, 223, 220, 0, 167, 29, 212, 26, 8, 244, 138, 244, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[13, 93, 35, 138, 74, 190, 152, 6, 135, 42, 73, 4, 89, 141, 109, 136, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[133, 163, 99, 102, 235, 113, 240, 65, 71, 166, 218, 43, 127, 134, 71, 80, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[5, 56, 97, 226, 5, 50, 115, 98, 140, 204, 132, 133, 178, 251, 62, 201, 32, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[52, 51, 210, 212, 51, 248, 129, 217, 127, 253, 45, 56, 253, 208, 115, 219, 64, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 10, 6, 60, 74, 7, 181, 18, 126, 255, 227, 196, 57, 234, 36, 134, 144, 128, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[20, 100, 62, 90, 228, 77, 18, 184, 245, 254, 229, 170, 67, 37, 109, 65, 165, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[203, 234, 111, 140, 235, 2, 187, 57, 155, 244, 248, 166, 159, 118, 68, 144, 114, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[7, 247, 40, 91, 129, 46, 27, 80, 64, 23, 145, 182, 130, 58, 158, 173, 164, 116, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[79, 167, 147, 147, 11, 205, 17, 34, 128, 235, 177, 33, 22, 74, 50, 200, 108, 136, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 28, 139, 195, 190, 118, 2, 171, 89, 9, 52, 235, 74, 222, 229, 251, 212, 61, 80, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[31, 29, 117, 165, 112, 156, 26, 177, 122, 92, 17, 48, 236, 180, 251, 214, 74, 101, 32, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 55, 38, 152, 118, 102, 25, 10, 238, 199, 152, 171, 233, 63, 17, 214, 94, 231, 243, 64, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[12, 39, 129, 244, 159, 252, 250, 109, 83, 203, 246, 183, 28, 118, 178, 95, 181, 15, 128, 128, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[121, 139, 19, 142, 63, 225, 200, 69, 69, 247, 163, 39, 28, 162, 247, 189, 18, 155, 5, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 191, 110, 195, 142, 126, 209, 210, 180, 187, 172, 95, 135, 30, 93, 173, 98, 186, 14, 50, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[47, 122, 83, 163, 144, 244, 50, 59, 15, 84, 187, 187, 71, 47, 168, 197, 219, 68, 141, 244, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 218, 199, 68, 99, 169, 137, 246, 78, 153, 79, 85, 80, 199, 220, 151, 186, 144, 173, 139, 136, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[18, 139, 200, 171, 228, 159, 99, 159, 17, 253, 25, 85, 39, 206, 157, 237, 73, 166, 199, 115, 80, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[185, 117, 214, 182, 238, 57, 228, 54, 179, 226, 253, 83, 142, 18, 43, 68, 224, 131, 202, 129, 32, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[7, 62, 154, 99, 37, 78, 66, 234, 35, 6, 221, 229, 67, 140, 181, 176, 176, 197, 37, 233, 11, 64, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[72, 114, 7, 223, 117, 14, 157, 37, 94, 68, 170, 244, 163, 127, 24, 230, 231, 179, 123, 26, 112, 128, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 212, 116, 78, 186, 146, 146, 35, 117, 174, 174, 173, 142, 98, 246, 249, 5, 13, 2, 207, 8, 101, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[28, 76, 139, 19, 73, 185, 181, 98, 152, 210, 210, 199, 143, 221, 165, 186, 50, 130, 28, 22, 83, 242, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 26, 253, 110, 192, 225, 65, 21, 217, 248, 60, 59, 203, 158, 168, 121, 69, 249, 21, 24, 223, 71, 116, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[11, 13, 230, 83, 136, 204, 138, 218, 131, 178, 90, 85, 244, 50, 148, 188, 187, 186, 210, 248, 184, 202, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[110, 138, 255, 67, 87, 253, 108, 137, 36, 247, 135, 91, 137, 249, 207, 95, 85, 76, 61, 183, 55, 233, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 81, 109, 248, 161, 111, 230, 61, 91, 113, 171, 73, 147, 99, 194, 25, 185, 84, 250, 105, 40, 47, 29, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[43, 46, 75, 182, 78, 94, 254, 101, 146, 112, 176, 223, 193, 229, 149, 1, 61, 81, 200, 27, 145, 215, 35, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 175, 206, 245, 31, 15, 181, 239, 247, 184, 102, 232, 189, 146, 247, 210, 12, 101, 49, 209, 19, 178, 103, 96, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[16, 222, 21, 147, 54, 157, 27, 95, 173, 52, 5, 23, 103, 189, 174, 52, 123, 243, 242, 42, 196, 248, 9, 197, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[168, 172, 215, 192, 34, 35, 17, 188, 196, 8, 50, 234, 13, 104, 206, 12, 215, 135, 117, 171, 177, 176, 97, 178, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[6, 150, 192, 109, 129, 85, 94, 177, 95, 168, 81, 253, 36, 134, 24, 12, 128, 107, 74, 152, 180, 240, 227, 208, 244, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[65, 227, 132, 71, 13, 85, 178, 237, 188, 147, 51, 227, 109, 60, 240, 125, 4, 48, 233, 247, 17, 104, 230, 41, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 146, 227, 42, 198, 133, 88, 253, 73, 93, 192, 6, 226, 68, 97, 100, 226, 41, 233, 35, 166, 174, 24, 253, 159, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[25, 188, 223, 171, 193, 53, 121, 228, 221, 169, 128, 68, 214, 171, 205, 240, 213, 163, 27, 100, 130, 204, 249, 232, 57, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 1, 96, 188, 181, 140, 22, 194, 240, 168, 159, 2, 176, 98, 182, 11, 104, 88, 95, 17, 237, 28, 1, 195, 18, 59, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[10, 13, 199, 95, 23, 120, 227, 157, 102, 150, 54, 26, 227, 219, 28, 114, 19, 115, 182, 179, 67, 24, 17, 158, 182, 80, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[100, 137, 201, 182, 234, 184, 228, 38, 1, 222, 29, 12, 230, 143, 28, 116, 194, 133, 35, 0, 158, 240, 176, 51, 31, 37, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 237, 97, 225, 37, 43, 56, 233, 124, 18, 173, 34, 129, 1, 151, 28, 143, 153, 51, 94, 6, 53, 102, 225, 255, 55, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[39, 69, 210, 203, 115, 176, 57, 30, 216, 186, 195, 89, 10, 15, 231, 29, 155, 252, 1, 172, 62, 22, 4, 211, 248, 42, 116, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 136, 186, 59, 242, 132, 226, 59, 52, 119, 75, 161, 122, 100, 159, 7, 40, 23, 216, 16, 186, 108, 220, 48, 71, 177, 168, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[15, 87, 70, 87, 121, 48, 214, 80, 12, 168, 244, 78, 199, 238, 54, 71, 144, 238, 112, 167, 72, 64, 153, 226, 204, 240, 149, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[153, 104, 191, 106, 187, 232, 95, 32, 126, 153, 139, 19, 207, 78, 30, 203, 169, 80, 102, 136, 210, 134, 2, 220, 1, 101, 213, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[5, 254, 23, 122, 43, 87, 19, 183, 68, 241, 255, 110, 198, 25, 13, 51, 244, 157, 36, 1, 88, 57, 60, 28, 152, 13, 250, 83, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[59, 236, 234, 197, 177, 102, 197, 40, 177, 115, 250, 83, 188, 250, 132, 7, 142, 35, 104, 13, 114, 60, 89, 29, 240, 139, 199, 64, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 87, 65, 43, 184, 238, 3, 179, 150, 238, 135, 199, 69, 97, 201, 40, 75, 141, 98, 16, 134, 118, 91, 123, 43, 101, 117, 200, 133, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[23, 104, 139, 181, 57, 76, 37, 3, 229, 81, 77, 200, 181, 209, 219, 146, 243, 133, 212, 165, 64, 159, 146, 207, 177, 246, 153, 213, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[234, 21, 117, 20, 60, 249, 114, 38, 245, 45, 9, 215, 26, 50, 147, 189, 131, 58, 78, 116, 134, 59, 188, 28, 243, 162, 2, 83, 244, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[9, 36, 214, 146, 202, 97, 190, 117, 133, 147, 194, 98, 103, 5, 249, 197, 103, 32, 71, 16, 141, 62, 85, 89, 33, 132, 84, 23, 71, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[91, 112, 97, 187, 231, 209, 112, 151, 55, 197, 151, 216, 6, 59, 193, 182, 7, 66, 198, 165, 132, 111, 85, 123, 79, 43, 72, 232, 203, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 146, 99, 209, 87, 14, 46, 101, 232, 45, 183, 238, 112, 62, 85, 145, 28, 72, 155, 194, 119, 44, 89, 86, 209, 23, 176, 217, 23, 241, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[35, 183, 230, 45, 102, 141, 207, 251, 17, 201, 47, 80, 98, 111, 87, 171, 26, 214, 21, 152, 167, 187, 125, 100, 42, 236, 232, 122, 239, 107, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 101, 46, 253, 198, 1, 138, 31, 206, 177, 219, 217, 35, 216, 89, 108, 175, 12, 92, 215, 246, 141, 82, 229, 233, 173, 65, 20, 205, 90, 48, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[13, 243, 213, 233, 188, 15, 101, 62, 18, 242, 150, 123, 102, 115, 126, 62, 214, 123, 160, 111, 161, 133, 60, 251, 32, 196, 138, 208, 5, 133, 229, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[139, 134, 91, 33, 88, 153, 244, 108, 189, 121, 224, 210, 0, 130, 238, 116, 96, 212, 68, 92, 79, 52, 97, 207, 71, 173, 108, 32, 55, 58, 242, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[5, 115, 63, 143, 77, 118, 3, 140, 63, 102, 194, 200, 52, 5, 29, 80, 139, 200, 74, 171, 155, 24, 11, 210, 24, 204, 198, 57, 66, 40, 77, 116, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[54, 128, 123, 153, 6, 156, 35, 122, 122, 3, 155, 210, 8, 51, 37, 37, 117, 210, 234, 180, 14, 240, 118, 52, 247, 255, 190, 60, 149, 147, 6, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 33, 4, 211, 250, 66, 25, 98, 200, 196, 36, 22, 52, 81, 255, 115, 118, 154, 61, 43, 8, 149, 100, 158, 17, 175, 253, 110, 93, 215, 190, 65, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[21, 74, 48, 71, 198, 148, 253, 219, 215, 169, 104, 222, 11, 51, 250, 130, 162, 6, 99, 174, 85, 213, 238, 44, 176, 223, 230, 79, 170, 109, 110, 141, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[212, 229, 226, 205, 193, 209, 234, 150, 108, 158, 24, 172, 112, 7, 201, 26, 84, 63, 228, 207, 90, 91, 77, 190, 232, 190, 255, 28, 168, 70, 81, 131, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[8, 80, 250, 220, 9, 146, 51, 41, 224, 62, 44, 246, 188, 96, 77, 219, 7, 74, 126, 240, 25, 135, 145, 9, 117, 23, 117, 247, 30, 146, 191, 47, 32, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[83, 41, 204, 152, 95, 181, 255, 162, 194, 109, 193, 163, 91, 195, 10, 142, 72, 232, 245, 96, 255, 75, 170, 94, 146, 234, 155, 167, 49, 187, 119, 215, 69, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[3, 63, 161, 253, 243, 189, 27, 252, 91, 152, 73, 144, 97, 149, 158, 105, 142, 217, 25, 149, 201, 248, 244, 167, 177, 189, 42, 20, 135, 241, 82, 174, 104, 178, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[32, 124, 83, 235, 133, 99, 23, 219, 147, 242, 223, 163, 207, 216, 48, 31, 148, 122, 255, 217, 227, 185, 142, 140, 241, 99, 164, 205, 79, 109, 58, 208, 22, 244, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 68, 219, 71, 51, 53, 222, 238, 147, 199, 124, 188, 102, 30, 113, 225, 59, 204, 205, 254, 130, 229, 63, 145, 129, 109, 228, 112, 5, 26, 68, 76, 32, 229, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[12, 176, 144, 200, 0, 26, 181, 81, 197, 202, 223, 91, 253, 48, 114, 204, 86, 0, 11, 241, 28, 244, 123, 175, 14, 74, 236, 96, 51, 6, 170, 249, 72, 247, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[126, 229, 167, 208, 1, 11, 21, 49, 185, 236, 185, 151, 227, 228, 123, 251, 92, 0, 119, 107, 33, 140, 212, 214, 142, 237, 59, 193, 254, 66, 173, 188, 217, 169, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 244, 248, 142, 32, 10, 110, 211, 241, 67, 63, 63, 238, 230, 236, 215, 209, 152, 4, 170, 47, 79, 128, 80, 97, 149, 68, 85, 147, 238, 154, 201, 96, 128, 155, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[49, 145, 181, 141, 64, 104, 84, 71, 108, 160, 120, 127, 85, 5, 64, 110, 47, 240, 46, 165, 217, 27, 3, 35, 207, 212, 171, 87, 199, 82, 11, 221, 197, 6, 16, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 239, 177, 23, 132, 132, 19, 74, 202, 62, 68, 180, 249, 82, 52, 132, 77, 223, 97, 210, 122, 123, 14, 31, 102, 30, 78, 177, 109, 201, 52, 118, 169, 178, 60, 165, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[19, 92, 234, 235, 45, 40, 192, 235, 230, 110, 175, 17, 189, 54, 13, 43, 10, 185, 210, 56, 200, 206, 141, 57, 253, 47, 18, 238, 73, 220, 12, 162, 160, 246, 94, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[193, 161, 45, 47, 195, 151, 137, 55, 0, 82, 214, 177, 100, 28, 131, 174, 107, 66, 54, 55, 216, 17, 132, 67, 227, 214, 189, 78, 226, 152, 126, 90, 73, 159, 176, 116, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[7, 144, 75, 195, 221, 163, 235, 92, 38, 3, 60, 98, 237, 233, 29, 36, 208, 48, 150, 30, 46, 112, 175, 42, 166, 230, 99, 101, 20, 217, 244, 239, 134, 224, 60, 228, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[75, 162, 245, 166, 168, 103, 49, 153, 124, 32, 91, 221, 75, 27, 35, 112, 33, 229, 221, 45, 208, 102, 215, 170, 132, 255, 225, 242, 208, 131, 145, 91, 68, 194, 96, 237, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 244, 93, 152, 130, 148, 7, 239, 254, 217, 67, 150, 164, 239, 15, 98, 97, 82, 250, 163, 202, 36, 4, 108, 169, 49, 254, 211, 124, 37, 35, 173, 144, 175, 151, 201, 69, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[29, 139, 167, 245, 25, 200, 79, 95, 244, 124, 163, 226, 113, 86, 153, 215, 205, 61, 202, 101, 229, 104, 44, 62, 155, 243, 244, 66, 217, 115, 100, 199, 166, 219, 237, 220, 179, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 39, 116, 143, 147, 1, 211, 25, 191, 140, 222, 102, 216, 109, 98, 2, 110, 4, 105, 231, 250, 246, 17, 186, 114, 23, 135, 138, 156, 126, 129, 239, 204, 132, 151, 74, 159, 0, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[11, 138, 141, 155, 190, 18, 63, 1, 123, 128, 176, 4, 116, 69, 212, 24, 76, 44, 35, 15, 205, 156, 177, 72, 116, 235, 75, 106, 28, 241, 19, 93, 253, 45, 232, 234, 54, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[115, 105, 136, 21, 108, 182, 118, 14, 211, 6, 224, 44, 138, 186, 72, 242, 249, 185, 94, 158, 8, 30, 236, 212, 145, 48, 242, 37, 33, 106, 193, 171, 227, 203, 25, 38, 28, 50, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 130, 31, 80, 214, 63, 32, 156, 148, 62, 68, 193, 189, 107, 70, 217, 125, 193, 61, 178, 44, 81, 53, 64, 77, 171, 233, 117, 115, 78, 43, 144, 182, 229, 238, 251, 125, 25, 244, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[45, 21, 57, 40, 94, 119, 70, 29, 202, 110, 175, 145, 102, 48, 196, 126, 233, 140, 104, 245, 187, 44, 20, 131, 8, 183, 30, 150, 129, 13, 179, 167, 36, 251, 85, 210, 227, 3, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 194, 212, 59, 147, 176, 168, 189, 41, 232, 82, 219, 173, 253, 231, 172, 245, 31, 124, 25, 153, 79, 184, 205, 30, 87, 39, 49, 225, 10, 137, 4, 135, 113, 209, 90, 60, 222, 35, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[17, 156, 74, 83, 196, 230, 151, 99, 163, 19, 60, 148, 203, 235, 12, 193, 147, 58, 216, 255, 253, 29, 56, 3, 47, 103, 135, 242, 202, 105, 90, 45, 74, 114, 45, 134, 96, 173, 97, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[176, 26, 231, 69, 177, 1, 233, 228, 94, 192, 93, 207, 247, 46, 127, 143, 192, 76, 121, 255, 227, 36, 48, 31, 218, 11, 79, 123, 232, 29, 133, 196, 232, 117, 199, 63, 198, 197, 203, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[6, 225, 13, 8, 184, 234, 19, 34, 235, 179, 131, 170, 31, 167, 208, 251, 157, 130, 252, 195, 254, 223, 105, 225, 62, 132, 113, 26, 215, 17, 39, 57, 177, 20, 153, 200, 125, 195, 185, 240, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[68, 202, 130, 87, 57, 36, 191, 93, 53, 3, 36, 165, 60, 142, 41, 212, 39, 29, 223, 167, 244, 186, 34, 204, 113, 44, 107, 12, 102, 171, 136, 64, 234, 206, 1, 212, 233, 165, 67, 101, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 175, 233, 23, 104, 59, 111, 121, 164, 18, 31, 110, 116, 93, 141, 162, 73, 135, 42, 188, 143, 143, 69, 91, 252, 107, 188, 46, 124, 2, 179, 82, 137, 44, 12, 18, 81, 32, 116, 161, 242, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[26, 223, 26, 234, 18, 82, 90, 192, 104, 181, 58, 80, 139, 167, 136, 86, 223, 71, 171, 93, 155, 152, 181, 151, 220, 53, 89, 208, 216, 27, 1, 57, 91, 184, 120, 183, 43, 68, 142, 83, 116, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 12, 183, 13, 36, 183, 55, 139, 132, 23, 20, 71, 37, 116, 139, 83, 100, 184, 204, 177, 168, 19, 247, 23, 238, 154, 21, 130, 40, 113, 14, 12, 61, 149, 52, 183, 39, 176, 173, 143, 66, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[10, 127, 38, 131, 111, 40, 43, 115, 40, 230, 202, 199, 118, 141, 113, 65, 239, 55, 254, 240, 144, 199, 166, 239, 82, 4, 215, 21, 148, 106, 140, 122, 103, 212, 15, 39, 140, 230, 199, 152, 153, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[104, 247, 129, 34, 87, 145, 178, 127, 153, 3, 235, 202, 161, 134, 108, 147, 88, 47, 245, 101, 167, 204, 133, 89, 52, 48, 102, 215, 204, 41, 124, 200, 14, 72, 151, 139, 129, 3, 203, 245, 253, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[4, 25, 171, 11, 87, 107, 176, 248, 251, 250, 39, 53, 234, 79, 64, 61, 193, 113, 223, 149, 248, 141, 253, 53, 124, 9, 228, 4, 109, 249, 158, 223, 208, 142, 213, 235, 115, 10, 37, 247, 155, 227, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[41, 0, 174, 113, 106, 52, 233, 185, 215, 197, 136, 27, 39, 24, 130, 105, 142, 114, 187, 219, 181, 139, 228, 22, 216, 98, 232, 44, 75, 192, 52, 190, 37, 148, 91, 50, 126, 101, 123, 172, 22, 224, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[1, 154, 6, 208, 110, 38, 17, 33, 66, 109, 183, 81, 15, 134, 245, 24, 31, 144, 123, 86, 149, 23, 118, 232, 228, 115, 221, 17, 186, 245, 130, 15, 109, 119, 203, 143, 248, 239, 246, 212, 184, 228, 197, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[16, 4, 68, 36, 77, 124, 171, 76, 152, 73, 41, 42, 155, 69, 146, 241, 59, 164, 209, 97, 210, 234, 165, 24, 236, 134, 162, 177, 77, 151, 20, 154, 70, 173, 243, 159, 185, 95, 164, 79, 56, 239, 178, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[160, 42, 169, 107, 6, 222, 176, 253, 242, 219, 155, 170, 16, 183, 189, 108, 84, 112, 45, 210, 61, 42, 114, 249, 61, 66, 90, 237, 7, 230, 206, 6, 194, 203, 132, 61, 61, 188, 107, 24, 57, 92, 244, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[6, 65, 170, 158, 46, 68, 178, 233, 235, 124, 148, 20, 164, 167, 45, 102, 59, 76, 97, 202, 54, 99, 168, 125, 188, 100, 151, 141, 66, 79, 4, 12, 67, 155, 243, 42, 100, 105, 92, 46, 242, 61, 161, 136, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[62, 144, 170, 45, 206, 174, 253, 35, 50, 221, 200, 206, 110, 135, 197, 254, 80, 251, 209, 230, 31, 228, 148, 233, 91, 237, 235, 132, 151, 22, 40, 122, 164, 23, 127, 167, 236, 29, 153, 213, 118, 104, 79, 80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[2, 113, 166, 165, 202, 18, 213, 227, 95, 252, 169, 216, 16, 81, 77, 187, 239, 41, 214, 50, 253, 62, 237, 209, 29, 151, 75, 51, 45, 230, 221, 148, 202, 104, 234, 252, 143, 57, 40, 2, 86, 160, 19, 25, 32, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[24, 112, 130, 121, 228, 188, 90, 225, 191, 222, 162, 112, 163, 45, 9, 87, 87, 162, 93, 253, 228, 117, 74, 43, 39, 232, 239, 255, 203, 4, 167, 207, 232, 25, 45, 221, 152, 59, 144, 23, 98, 64, 190, 251, 64, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[244, 101, 24, 194, 239, 91, 140, 209, 126, 178, 88, 102, 95, 194, 93, 105, 108, 87, 171, 234, 236, 148, 229, 175, 143, 25, 95, 253, 238, 46, 142, 31, 16, 251, 202, 167, 242, 83, 160, 233, 214, 135, 117, 208, 128, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[9, 139, 242, 247, 157, 89, 147, 128, 46, 242, 247, 115, 255, 189, 151, 166, 30, 59, 108, 183, 45, 61, 208, 248, 219, 150, 253, 191, 235, 77, 209, 141, 54, 169, 213, 234, 143, 119, 68, 73, 34, 97, 74, 154, 37, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[95, 119, 125, 172, 37, 127, 195, 1, 213, 125, 170, 135, 253, 103, 236, 125, 46, 82, 63, 39, 196, 106, 41, 184, 147, 229, 233, 127, 49, 10, 47, 132, 34, 162, 91, 41, 154, 168, 170, 219, 87, 204, 234, 5, 114, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    uint512(cast(const(ubyte)[])[190, 238, 251, 88, 74, 255, 134, 3, 170, 251, 85, 15, 250, 207, 216, 250, 92, 164, 126, 79, 136, 212, 83, 113, 39, 203, 210, 254, 98, 20, 95, 8, 69, 68, 182, 83, 53, 81, 85, 182, 175, 153, 212, 10, 228, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), // uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"),
    ];

version(ShowEnumDecBytes)
unittest
{
    static assert(pow10RoundEven_512[0 + 19]   == uint512("50000000000000000000")); // 19
    static assert(pow10RoundEven_512[1 + 19]   == uint512("500000000000000000000"));
    static assert(pow10RoundEven_512[2 + 19]   == uint512("5000000000000000000000"));
    static assert(pow10RoundEven_512[3 + 19]   == uint512("50000000000000000000000"));
    static assert(pow10RoundEven_512[4 + 19]   == uint512("500000000000000000000000"));
    static assert(pow10RoundEven_512[5 + 19]   == uint512("5000000000000000000000000"));
    static assert(pow10RoundEven_512[6 + 19]   == uint512("50000000000000000000000000"));
    static assert(pow10RoundEven_512[7 + 19]   == uint512("500000000000000000000000000"));
    static assert(pow10RoundEven_512[8 + 19]   == uint512("5000000000000000000000000000"));
    static assert(pow10RoundEven_512[9 + 19]   == uint512("50000000000000000000000000000"));
    static assert(pow10RoundEven_512[10 + 19]  == uint512("500000000000000000000000000000"));
    static assert(pow10RoundEven_512[11 + 19]  == uint512("5000000000000000000000000000000"));
    static assert(pow10RoundEven_512[12 + 19]  == uint512("50000000000000000000000000000000"));
    static assert(pow10RoundEven_512[13 + 19]  == uint512("500000000000000000000000000000000"));
    static assert(pow10RoundEven_512[14 + 19]  == uint512("5000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[15 + 19]  == uint512("50000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[16 + 19]  == uint512("500000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[17 + 19]  == uint512("5000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[18 + 19]  == uint512("50000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[19 + 19]  == uint512("500000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[20 + 19]  == uint512("5000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[21 + 19]  == uint512("50000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[22 + 19]  == uint512("500000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[23 + 19]  == uint512("5000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[24 + 19]  == uint512("50000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[25 + 19]  == uint512("500000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[26 + 19]  == uint512("5000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[27 + 19]  == uint512("50000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[28 + 19]  == uint512("500000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[29 + 19]  == uint512("5000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[30 + 19]  == uint512("50000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[31 + 19]  == uint512("500000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[32 + 19]  == uint512("5000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[33 + 19]  == uint512("50000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[34 + 19]  == uint512("500000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[35 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[36 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[37 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[38 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[39 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[40 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[41 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[42 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[43 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[44 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[45 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[46 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[47 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[48 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[49 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[50 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[51 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[52 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[53 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[54 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[55 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[56 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[57 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[58 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[59 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[60 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[61 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[62 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[63 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[64 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[65 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[66 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[67 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[68 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[69 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[70 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[71 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[72 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[73 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[74 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[75 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[76 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[77 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[78 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[79 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[80 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[81 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[82 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[83 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[84 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[85 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[86 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[87 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[88 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[89 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[90 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[91 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[92 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[93 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[94 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[95 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[96 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[97 + 19]  == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[98 + 19]  == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[99 + 19]  == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[100 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[101 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[102 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[103 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[104 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[105 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[106 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[107 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[108 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[109 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[110 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[111 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[112 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[113 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[114 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[115 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[116 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[117 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[118 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[119 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[120 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[121 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[122 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[123 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[124 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[125 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[126 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[127 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[128 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[129 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[130 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[131 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[132 + 19] == uint512("50000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[133 + 19] == uint512("500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[134 + 19] == uint512("5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
    static assert(pow10RoundEven_512[135 + 19] == uint512("10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"));
}

template pow10RoundEven(T)
{
    alias UT = Unqual!T;

    static if (is(UT == uint))
        alias pow10RoundEven = pow10RoundEven_32;
    else static if (is(UT == ulong))
        alias pow10RoundEven = pow10RoundEven_64;
    else static if (is(UT == uint128))
        alias pow10RoundEven = pow10RoundEven_128;
    else static if (is(UT == uint256))
        alias pow10RoundEven = pow10RoundEven_256;
    else static if (is(UT == uint512))
        alias pow10RoundEven = pow10RoundEven_512;
    else static if (is(UT == ushort))
        alias pow10RoundEven = pow10RoundEven_16;
    else static if (is(UT == ubyte))
        alias pow10RoundEven = pow10RoundEven_8;
    else
        static assert(0);
}

int pow10RoundEvenIndex(T)(int index)
{
    alias table = pow10RoundEven!T;
    return index < 0 ? 0 : (index >= table.length ? table.length - 1 : index);
}

/* ****************************************************************************************************************** */
/* MAXIMUM COEFFICIENTS THAT CAN BE MULTIPLIED BY 10-POWERS                                                                                                */
/* ****************************************************************************************************************** */

static immutable ubyte[3] maxmul10_8 = [
    255U,
    25U,
    2U,
    ];

static immutable ushort[5] maxmul10_16 = [
    65535U,
    6553U,
    655U,
    65U,
    6U,
    ];

static immutable uint[10] maxmul10_32 = [
    4294967295U,
    429496729U,
    42949672U,
    4294967U,
    429496U,
    42949U,
    4294U,
    429U,
    42U,
    4U,
    ];

static immutable ulong[20] maxmul10_64 = [
    18446744073709551615UL,
    1844674407370955161UL,
    184467440737095516UL,
    18446744073709551UL,
    1844674407370955UL,
    184467440737095UL,
    18446744073709UL,
    1844674407370UL,
    184467440737UL,
    18446744073UL,
    1844674407UL,
    184467440UL,
    18446744UL,
    1844674UL,
    184467UL,
    18446UL,
    1844UL,
    184UL,
    18UL,
    1UL,
    ];

static immutable uint128[39] maxmul10_128 = [
    uint128(cast(const(ubyte)[])[255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255]), // uint128("340282366920938463463374607431768211455"),
    uint128(cast(const(ubyte)[])[25, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153]),  // uint128("34028236692093846346337460743176821145"),
    uint128(cast(const(ubyte)[])[2, 143, 92, 40, 245, 194, 143, 92, 40, 245, 194, 143, 92, 40, 245, 194]),         // uint128("3402823669209384634633746074317682114"),
    uint128(cast(const(ubyte)[])[65, 137, 55, 75, 198, 167, 239, 157, 178, 45, 14, 86, 4, 24, 147]),            // uint128("340282366920938463463374607431768211"),
    uint128(cast(const(ubyte)[])[6, 141, 184, 186, 199, 16, 203, 41, 94, 158, 27, 8, 154, 2, 117]),             // uint128("34028236692093846346337460743176821"),
    uint128(cast(const(ubyte)[])[167, 197, 172, 71, 27, 71, 132, 35, 15, 207, 128, 220, 51, 114]),           // uint128("3402823669209384634633746074317682"),
    uint128(cast(const(ubyte)[])[16, 198, 247, 160, 181, 237, 141, 54, 180, 199, 243, 73, 56, 88]),          // uint128("340282366920938463463374607431768"),
    uint128(cast(const(ubyte)[])[1, 173, 127, 41, 171, 202, 244, 133, 120, 122, 101, 32, 236, 8]),           // uint128("34028236692093846346337460743176"),
    uint128(cast(const(ubyte)[])[42, 243, 29, 196, 97, 24, 115, 191, 63, 112, 131, 74, 205]),             // uint128("3402823669209384634633746074317"),
    uint128(cast(const(ubyte)[])[4, 75, 130, 250, 9, 181, 165, 44, 185, 139, 64, 84, 71]),                // uint128("340282366920938463463374607431"),
    uint128(cast(const(ubyte)[])[109, 243, 127, 103, 94, 246, 234, 223, 90, 185, 162, 7]),             // uint128("34028236692093846346337460743"),
    uint128(cast(const(ubyte)[])[10, 254, 191, 240, 188, 178, 74, 175, 239, 120, 246, 154]),           // uint128("3402823669209384634633746074"),
    uint128(cast(const(ubyte)[])[1, 25, 121, 152, 18, 222, 161, 17, 151, 242, 127, 15]),               // uint128("340282366920938463463374607"),
    uint128(cast(const(ubyte)[])[28, 37, 194, 104, 73, 118, 129, 194, 101, 12, 180]),               // uint128("34028236692093846346337460"),
    uint128(cast(const(ubyte)[])[2, 208, 147, 112, 212, 37, 115, 96, 61, 78, 18]),                  // uint128("3402823669209384634633746"),
    uint128(cast(const(ubyte)[])[72, 14, 190, 123, 157, 88, 86, 108, 135, 206]),                 // uint128("340282366920938463463374"),
    uint128(cast(const(ubyte)[])[7, 52, 172, 165, 246, 34, 111, 10, 218, 97]),                   // uint128("34028236692093846346337"),
    uint128(cast(const(ubyte)[])[184, 119, 170, 50, 54, 164, 180, 73, 9]),                    // uint128("3402823669209384634633"),
    uint128(cast(const(ubyte)[])[18, 114, 93, 209, 210, 67, 171, 160, 231]),                  // uint128("340282366920938463463"),
    uint128(cast(const(ubyte)[])[1, 216, 60, 148, 251, 109, 42, 195, 74]),                    // uint128("34028236692093846346"),
    uint128(3402823669209384634UL),
    uint128(340282366920938463UL),
    uint128(34028236692093846UL),
    uint128(3402823669209384UL),
    uint128(340282366920938UL),
    uint128(34028236692093UL),
    uint128(3402823669209UL),
    uint128(340282366920UL),
    uint128(34028236692UL),
    uint128(3402823669UL),
    uint128(340282366UL),
    uint128(34028236UL),
    uint128(3402823UL),
    uint128(340282UL),
    uint128(34028UL),
    uint128(3402UL),
    uint128(340UL),
    uint128(34UL),
    uint128(3UL),
    ];

version(ShowEnumDecBytes)
unittest
{
    static assert(maxmul10_128[0]  == uint128("340282366920938463463374607431768211455"));
    static assert(maxmul10_128[1]  == uint128("34028236692093846346337460743176821145"));
    static assert(maxmul10_128[2]  == uint128("3402823669209384634633746074317682114"));
    static assert(maxmul10_128[3]  == uint128("340282366920938463463374607431768211"));
    static assert(maxmul10_128[4]  == uint128("34028236692093846346337460743176821"));
    static assert(maxmul10_128[5]  == uint128("3402823669209384634633746074317682"));
    static assert(maxmul10_128[6]  == uint128("340282366920938463463374607431768"));
    static assert(maxmul10_128[7]  == uint128("34028236692093846346337460743176"));
    static assert(maxmul10_128[8]  == uint128("3402823669209384634633746074317"));
    static assert(maxmul10_128[9]  == uint128("340282366920938463463374607431"));
    static assert(maxmul10_128[10] == uint128("34028236692093846346337460743"));
    static assert(maxmul10_128[11] == uint128("3402823669209384634633746074"));
    static assert(maxmul10_128[12] == uint128("340282366920938463463374607"));
    static assert(maxmul10_128[13] == uint128("34028236692093846346337460"));
    static assert(maxmul10_128[14] == uint128("3402823669209384634633746"));
    static assert(maxmul10_128[15] == uint128("340282366920938463463374"));
    static assert(maxmul10_128[16] == uint128("34028236692093846346337"));
    static assert(maxmul10_128[17] == uint128("3402823669209384634633"));
    static assert(maxmul10_128[18] == uint128("340282366920938463463"));
    static assert(maxmul10_128[19] == uint128("34028236692093846346"));
}

static immutable uint256[78] maxmul10_256 = [
    uint256(cast(const(ubyte)[])[255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255]), //uint256("115792089237316195423570985008687907853269984665640564039457584007913129639935"),
    uint256(cast(const(ubyte)[])[25, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153, 153]), //uint256("11579208923731619542357098500868790785326998466564056403945758400791312963993"),
    uint256(cast(const(ubyte)[])[2, 143, 92, 40, 245, 194, 143, 92, 40, 245, 194, 143, 92, 40, 245, 194, 143, 92, 40, 245, 194, 143, 92, 40, 245, 194, 143, 92, 40, 245, 194, 143]), //uint256("1157920892373161954235709850086879078532699846656405640394575840079131296399"),
    uint256(cast(const(ubyte)[])[65, 137, 55, 75, 198, 167, 239, 157, 178, 45, 14, 86, 4, 24, 147, 116, 188, 106, 126, 249, 219, 34, 208, 229, 96, 65, 137, 55, 75, 198, 167]), //uint256("115792089237316195423570985008687907853269984665640564039457584007913129639"),
    uint256(cast(const(ubyte)[])[6, 141, 184, 186, 199, 16, 203, 41, 94, 158, 27, 8, 154, 2, 117, 37, 70, 10, 166, 76, 47, 131, 123, 74, 35, 57, 192, 235, 237, 250, 67]), //uint256("11579208923731619542357098500868790785326998466564056403945758400791312963"),
    uint256(cast(const(ubyte)[])[167, 197, 172, 71, 27, 71, 132, 35, 15, 207, 128, 220, 51, 114, 29, 83, 205, 221, 110, 4, 192, 89, 33, 3, 133, 198, 125, 254, 50, 160]), //uint256("1157920892373161954235709850086879078532699846656405640394575840079131296"),
    uint256(cast(const(ubyte)[])[16, 198, 247, 160, 181, 237, 141, 54, 180, 199, 243, 73, 56, 88, 54, 33, 250, 252, 139, 0, 121, 162, 131, 77, 38, 250, 63, 204, 158, 169]), //uint256("115792089237316195423570985008687907853269984665640564039457584007913129"),
    uint256(cast(const(ubyte)[])[1, 173, 127, 41, 171, 202, 244, 133, 120, 122, 101, 32, 236, 8, 210, 54, 153, 25, 65, 25, 165, 195, 115, 135, 183, 25, 6, 97, 67, 16]), //uint256("11579208923731619542357098500868790785326998466564056403945758400791312"),
    uint256(cast(const(ubyte)[])[42, 243, 29, 196, 97, 24, 115, 191, 63, 112, 131, 74, 205, 174, 159, 15, 79, 83, 79, 93, 96, 88, 90, 95, 28, 26, 60, 237, 27]), //uint256("1157920892373161954235709850086879078532699846656405640394575840079131"),
    uint256(cast(const(ubyte)[])[4, 75, 130, 250, 9, 181, 165, 44, 185, 139, 64, 84, 71, 196, 169, 129, 135, 238, 187, 34, 240, 8, 213, 214, 79, 156, 57, 74, 233]), //uint256("115792089237316195423570985008687907853269984665640564039457584007913"),
    uint256(cast(const(ubyte)[])[109, 243, 127, 103, 94, 246, 234, 223, 90, 185, 162, 7, 45, 68, 38, 141, 151, 223, 131, 126, 103, 72, 149, 110, 92, 108, 33, 23]), //uint256("11579208923731619542357098500868790785326998466564056403945758400791"),
    uint256(cast(const(ubyte)[])[10, 254, 191, 240, 188, 178, 74, 175, 239, 120, 246, 154, 81, 83, 157, 116, 143, 47, 243, 140, 163, 237, 168, 139, 9, 62, 3, 79]), //uint256("1157920892373161954235709850086879078532699846656405640394575840079"),
    uint256(cast(const(ubyte)[])[1, 25, 121, 152, 18, 222, 161, 17, 151, 242, 127, 15, 110, 136, 92, 139, 167, 235, 49, 244, 118, 202, 247, 65, 26, 134, 51, 135]), //uint256("115792089237316195423570985008687907853269984665640564039457584007"),
    uint256(cast(const(ubyte)[])[28, 37, 194, 104, 73, 118, 129, 194, 101, 12, 180, 190, 64, 214, 13, 247, 49, 30, 152, 114, 71, 127, 32, 28, 64, 158, 192]), //uint256("11579208923731619542357098500868790785326998466564056403945758400"),
    uint256(cast(const(ubyte)[])[2, 208, 147, 112, 212, 37, 115, 96, 61, 78, 18, 19, 6, 123, 206, 50, 81, 182, 66, 113, 211, 243, 28, 207, 160, 15, 224]), //uint256("1157920892373161954235709850086879078532699846656405640394575840"),
    uint256(cast(const(ubyte)[])[72, 14, 190, 123, 157, 88, 86, 108, 135, 206, 155, 128, 165, 251, 5, 8, 43, 211, 113, 200, 101, 28, 123, 41, 155, 48]), //uint256("115792089237316195423570985008687907853269984665640564039457584"),
    uint256(cast(const(ubyte)[])[7, 52, 172, 165, 246, 34, 111, 10, 218, 97, 117, 243, 67, 204, 77, 77, 157, 251, 139, 96, 214, 233, 63, 132, 41, 30]), //uint256("11579208923731619542357098500868790785326998466564056403945758"),
    uint256(cast(const(ubyte)[])[184, 119, 170, 50, 54, 164, 180, 73, 9, 190, 254, 185, 250, 212, 135, 194, 255, 141, 240, 21, 125, 185, 141, 55, 79]), //uint256("1157920892373161954235709850086879078532699846656405640394575"),
    uint256(cast(const(ubyte)[])[18, 114, 93, 209, 210, 67, 171, 160, 231, 95, 230, 69, 204, 72, 115, 249, 230, 90, 254, 104, 140, 146, 142, 31, 33]), //uint256("115792089237316195423570985008687907853269984665640564039457"),
    uint256(cast(const(ubyte)[])[1, 216, 60, 148, 251, 109, 42, 195, 74, 86, 99, 211, 199, 160, 216, 101, 202, 60, 76, 164, 14, 14, 167, 207, 233]), //uint256("11579208923731619542357098500868790785326998466564056403945"),
    uint256(cast(const(ubyte)[])[47, 57, 66, 25, 36, 132, 70, 186, 162, 61, 46, 199, 41, 175, 61, 97, 6, 7, 170, 1, 103, 221, 148, 202]), //uint256("1157920892373161954235709850086879078532699846656405640394"),
    uint256(cast(const(ubyte)[])[4, 184, 237, 2, 131, 166, 211, 223, 118, 159, 183, 224, 183, 94, 82, 240, 26, 51, 247, 102, 138, 98, 245, 71]), //uint256("115792089237316195423570985008687907853269984665640564039"),
    uint256(cast(const(ubyte)[])[120, 228, 128, 64, 93, 123, 150, 88, 169, 146, 99, 69, 137, 110, 177, 156, 56, 101, 138, 65, 9, 229, 83]), //uint256("11579208923731619542357098500868790785326998466564056403"),
    uint256(cast(const(ubyte)[])[12, 22, 217, 160, 9, 89, 40, 162, 119, 91, 112, 83, 192, 241, 120, 41, 56, 214, 244, 57, 180, 48, 136]), //uint256("1157920892373161954235709850086879078532699846656405640"),
    uint256(cast(const(ubyte)[])[1, 53, 124, 41, 154, 136, 234, 118, 165, 137, 36, 213, 44, 228, 242, 106, 133, 175, 24, 108, 43, 158, 116]), //uint256("115792089237316195423570985008687907853269984665640564"),
    uint256(cast(const(ubyte)[])[30, 242, 208, 245, 218, 125, 216, 170, 39, 80, 123, 183, 176, 126, 164, 64, 145, 130, 113, 55, 143, 216]), //uint256("11579208923731619542357098500868790785326998466564056"),
    uint256(cast(const(ubyte)[])[3, 24, 72, 24, 149, 217, 98, 119, 106, 84, 217, 43, 248, 12, 170, 6, 116, 243, 113, 184, 193, 149]), //uint256("1157920892373161954235709850086879078532699846656405"),
    uint256(cast(const(ubyte)[])[79, 58, 104, 219, 200, 240, 63, 36, 59, 175, 81, 50, 103, 170, 154, 62, 229, 36, 248, 224, 40]), //uint256("115792089237316195423570985008687907853269984665640"),
    uint256(cast(const(ubyte)[])[7, 236, 61, 175, 148, 24, 6, 80, 108, 94, 84, 235, 112, 196, 66, 159, 227, 182, 229, 176, 4]), //uint256("11579208923731619542357098500868790785326998466564"),
    uint256(cast(const(ubyte)[])[202, 210, 247, 245, 53, 154, 59, 62, 9, 110, 228, 88, 19, 160, 67, 48, 95, 22, 248, 0]), //uint256("1157920892373161954235709850086879078532699846656"),
    uint256(cast(const(ubyte)[])[20, 72, 75, 254, 235, 194, 159, 134, 52, 36, 176, 111, 53, 41, 160, 81, 163, 27, 229, 153]), //uint256("115792089237316195423570985008687907853269984665"),
    uint256(cast(const(ubyte)[])[2, 7, 58, 204, 177, 45, 15, 243, 210, 3, 171, 62, 82, 29, 195, 59, 93, 28, 99, 194]), //uint256("11579208923731619542357098500868790785326998466"),
    uint256(cast(const(ubyte)[])[51, 236, 71, 171, 81, 78, 101, 46, 153, 247, 134, 59, 105, 96, 82, 188, 130, 214, 198]), //uint256("1157920892373161954235709850086879078532699846"),
    uint256(cast(const(ubyte)[])[5, 49, 58, 93, 238, 135, 214, 235, 15, 101, 141, 108, 87, 86, 110, 172, 115, 123, 224]), //uint256("115792089237316195423570985008687907853269984"),
    uint256(cast(const(ubyte)[])[132, 236, 60, 151, 218, 98, 74, 180, 189, 90, 241, 59, 239, 11, 17, 62, 191, 150]), //uint256("11579208923731619542357098500868790785326998"),
    uint256(cast(const(ubyte)[])[13, 74, 210, 219, 252, 61, 7, 120, 121, 85, 228, 236, 100, 180, 78, 134, 70, 91]), //uint256("1157920892373161954235709850086879078532699"),
    uint256(cast(const(ubyte)[])[1, 84, 72, 73, 50, 210, 231, 37, 165, 187, 202, 23, 163, 171, 161, 115, 211, 213]), //uint256("115792089237316195423570985008687907853269"),
    uint256(cast(const(ubyte)[])[34, 7, 58, 133, 21, 23, 29, 93, 95, 148, 53, 144, 93, 246, 139, 149, 46]), //uint256("11579208923731619542357098500868790785326"),
    uint256(cast(const(ubyte)[])[3, 103, 31, 115, 181, 79, 28, 137, 86, 91, 158, 244, 214, 50, 65, 40, 132]), //uint256("1157920892373161954235709850086879078532"),
    uint256(cast(const(ubyte)[])[87, 28, 190, 197, 84, 182, 13, 187, 213, 246, 75, 175, 5, 6, 132, 13]), //uint256("115792089237316195423570985008687907853"),
    uint256(cast(const(ubyte)[])[8, 182, 19, 19, 187, 171, 206, 44, 98, 50, 58, 196, 179, 179, 218, 1]), //uint256("11579208923731619542357098500868790785"),
    uint256(cast(const(ubyte)[])[223, 1, 232, 95, 145, 46, 55, 163, 107, 108, 70, 222, 197, 47, 102]), //uint256("1157920892373161954235709850086879078"),
    uint256(cast(const(ubyte)[])[22, 76, 253, 163, 40, 30, 56, 195, 138, 190, 7, 22, 70, 235, 35]), //uint256("115792089237316195423570985008687907"),
    uint256(cast(const(ubyte)[])[2, 58, 230, 41, 234, 105, 108, 19, 141, 223, 205, 130, 58, 74, 182]), //uint256("11579208923731619542357098500868790"),
    uint256(cast(const(ubyte)[])[57, 23, 4, 49, 10, 138, 206, 193, 99, 46, 38, 159, 109, 223]), //uint256("1157920892373161954235709850086879"),
    uint256(cast(const(ubyte)[])[5, 181, 128, 107, 77, 218, 174, 70, 137, 235, 3, 220, 190, 47]), //uint256("115792089237316195423570985008687"),
    uint256(cast(const(ubyte)[])[146, 38, 113, 33, 98, 171, 7, 13, 202, 179, 150, 19, 4]), //uint256("11579208923731619542357098500868"),
    uint256(cast(const(ubyte)[])[14, 157, 113, 182, 137, 221, 231, 26, 250, 171, 143, 1, 230]), //uint256("1157920892373161954235709850086"),
    uint256(cast(const(ubyte)[])[1, 118, 36, 248, 167, 98, 253, 130, 178, 170, 193, 128, 48]), //uint256("115792089237316195423570985008"),
    uint256(cast(const(ubyte)[])[37, 106, 24, 221, 137, 230, 38, 171, 119, 121, 192, 4]), //uint256("11579208923731619542357098500"),
    uint256(cast(const(ubyte)[])[3, 189, 207, 73, 90, 151, 3, 221, 242, 88, 249, 154]), //uint256("1157920892373161954235709850"),
    uint256(cast(const(ubyte)[])[95, 199, 237, 188, 66, 77, 47, 203, 111, 76, 41]), //uint256("115792089237316195423570985"),
    uint256(cast(const(ubyte)[])[9, 147, 254, 44, 109, 7, 183, 250, 190, 84, 106]), //uint256("11579208923731619542357098"),
    uint256(cast(const(ubyte)[])[245, 51, 4, 113, 77, 146, 101, 223, 213, 61]), //uint256("1157920892373161954235709"),
    uint256(cast(const(ubyte)[])[24, 133, 26, 11, 84, 142, 163, 201, 149, 82]), //uint256("115792089237316195423570"),
    uint256(cast(const(ubyte)[])[2, 115, 181, 205, 238, 219, 16, 96, 245, 85]), //uint256("11579208923731619542357"),
    uint256(cast(const(ubyte)[])[62, 197, 97, 100, 175, 129, 163, 75, 187]), //uint256("1157920892373161954235"),
    uint256(cast(const(ubyte)[])[6, 70, 240, 35, 171, 38, 144, 84, 95]), //uint256("115792089237316195423"),
    uint256(cast(const(ubyte)[])[160, 177, 157, 42, 183, 14, 110, 214]), //uint256("11579208923731619542"),
    uint256(cast(const(ubyte)[])[16, 17, 194, 234, 171, 231, 215, 226]), //uint256("1157920892373161954"),
    uint256(cast(const(ubyte)[])[1, 155, 96, 74, 170, 202, 98, 99]), //uint256("115792089237316195"),
    uint256(11579208923731619UL),
    uint256(1157920892373161UL),
    uint256(115792089237316UL),
    uint256(11579208923731UL),
    uint256(1157920892373UL),
    uint256(115792089237UL),
    uint256(11579208923UL),
    uint256(1157920892UL),
    uint256(115792089UL),
    uint256(11579208UL),
    uint256(1157920UL),
    uint256(115792UL),
    uint256(11579UL),
    uint256(1157UL),
    uint256(115UL),
    uint256(11UL),
    uint256(1UL),
    ];

version(ShowEnumDecBytes)
unittest
{
    static assert(maxmul10_256[0]  == uint256("115792089237316195423570985008687907853269984665640564039457584007913129639935"));
    static assert(maxmul10_256[1]  == uint256("11579208923731619542357098500868790785326998466564056403945758400791312963993"));
    static assert(maxmul10_256[2]  == uint256("1157920892373161954235709850086879078532699846656405640394575840079131296399"));
    static assert(maxmul10_256[3]  == uint256("115792089237316195423570985008687907853269984665640564039457584007913129639"));
    static assert(maxmul10_256[4]  == uint256("11579208923731619542357098500868790785326998466564056403945758400791312963"));
    static assert(maxmul10_256[5]  == uint256("1157920892373161954235709850086879078532699846656405640394575840079131296"));
    static assert(maxmul10_256[6]  == uint256("115792089237316195423570985008687907853269984665640564039457584007913129"));
    static assert(maxmul10_256[7]  == uint256("11579208923731619542357098500868790785326998466564056403945758400791312"));
    static assert(maxmul10_256[8]  == uint256("1157920892373161954235709850086879078532699846656405640394575840079131"));
    static assert(maxmul10_256[9]  == uint256("115792089237316195423570985008687907853269984665640564039457584007913"));
    static assert(maxmul10_256[10] == uint256("11579208923731619542357098500868790785326998466564056403945758400791"));
    static assert(maxmul10_256[11] == uint256("1157920892373161954235709850086879078532699846656405640394575840079"));
    static assert(maxmul10_256[12] == uint256("115792089237316195423570985008687907853269984665640564039457584007"));
    static assert(maxmul10_256[13] == uint256("11579208923731619542357098500868790785326998466564056403945758400"));
    static assert(maxmul10_256[14] == uint256("1157920892373161954235709850086879078532699846656405640394575840"));
    static assert(maxmul10_256[15] == uint256("115792089237316195423570985008687907853269984665640564039457584"));
    static assert(maxmul10_256[16] == uint256("11579208923731619542357098500868790785326998466564056403945758"));
    static assert(maxmul10_256[17] == uint256("1157920892373161954235709850086879078532699846656405640394575"));
    static assert(maxmul10_256[18] == uint256("115792089237316195423570985008687907853269984665640564039457"));
    static assert(maxmul10_256[19] == uint256("11579208923731619542357098500868790785326998466564056403945"));
    static assert(maxmul10_256[20] == uint256("1157920892373161954235709850086879078532699846656405640394"));
    static assert(maxmul10_256[21] == uint256("115792089237316195423570985008687907853269984665640564039"));
    static assert(maxmul10_256[22] == uint256("11579208923731619542357098500868790785326998466564056403"));
    static assert(maxmul10_256[23] == uint256("1157920892373161954235709850086879078532699846656405640"));
    static assert(maxmul10_256[24] == uint256("115792089237316195423570985008687907853269984665640564"));
    static assert(maxmul10_256[25] == uint256("11579208923731619542357098500868790785326998466564056"));
    static assert(maxmul10_256[26] == uint256("1157920892373161954235709850086879078532699846656405"));
    static assert(maxmul10_256[27] == uint256("115792089237316195423570985008687907853269984665640"));
    static assert(maxmul10_256[28] == uint256("11579208923731619542357098500868790785326998466564"));
    static assert(maxmul10_256[29] == uint256("1157920892373161954235709850086879078532699846656"));
    static assert(maxmul10_256[30] == uint256("115792089237316195423570985008687907853269984665"));
    static assert(maxmul10_256[31] == uint256("11579208923731619542357098500868790785326998466"));
    static assert(maxmul10_256[32] == uint256("1157920892373161954235709850086879078532699846"));
    static assert(maxmul10_256[33] == uint256("115792089237316195423570985008687907853269984"));
    static assert(maxmul10_256[34] == uint256("11579208923731619542357098500868790785326998"));
    static assert(maxmul10_256[35] == uint256("1157920892373161954235709850086879078532699"));
    static assert(maxmul10_256[36] == uint256("115792089237316195423570985008687907853269"));
    static assert(maxmul10_256[37] == uint256("11579208923731619542357098500868790785326"));
    static assert(maxmul10_256[38] == uint256("1157920892373161954235709850086879078532"));
    static assert(maxmul10_256[39] == uint256("115792089237316195423570985008687907853"));
    static assert(maxmul10_256[40] == uint256("11579208923731619542357098500868790785"));
    static assert(maxmul10_256[41] == uint256("1157920892373161954235709850086879078"));
    static assert(maxmul10_256[42] == uint256("115792089237316195423570985008687907"));
    static assert(maxmul10_256[43] == uint256("11579208923731619542357098500868790"));
    static assert(maxmul10_256[44] == uint256("1157920892373161954235709850086879"));
    static assert(maxmul10_256[45] == uint256("115792089237316195423570985008687"));
    static assert(maxmul10_256[46] == uint256("11579208923731619542357098500868"));
    static assert(maxmul10_256[47] == uint256("1157920892373161954235709850086"));
    static assert(maxmul10_256[48] == uint256("115792089237316195423570985008"));
    static assert(maxmul10_256[49] == uint256("11579208923731619542357098500"));
    static assert(maxmul10_256[50] == uint256("1157920892373161954235709850"));
    static assert(maxmul10_256[51] == uint256("115792089237316195423570985"));
    static assert(maxmul10_256[52] == uint256("11579208923731619542357098"));
    static assert(maxmul10_256[53] == uint256("1157920892373161954235709"));
    static assert(maxmul10_256[54] == uint256("115792089237316195423570"));
    static assert(maxmul10_256[55] == uint256("11579208923731619542357"));
    static assert(maxmul10_256[56] == uint256("1157920892373161954235"));
    static assert(maxmul10_256[57] == uint256("115792089237316195423"));
    static assert(maxmul10_256[58] == uint256("11579208923731619542"));
    static assert(maxmul10_256[59] == uint256("1157920892373161954"));
    static assert(maxmul10_256[60] == uint256("115792089237316195"));
}

template maxmul10(T)
{
    alias UT = Unqual!T;

    static if (is(UT == uint))
        alias maxmul10 = maxmul10_32;
    else static if (is(UT == ulong))
        alias maxmul10 = maxmul10_64;
    else static if (is(UT == uint128))
        alias maxmul10 = maxmul10_128;
    else static if (is(UT == uint256))
        alias maxmul10 = maxmul10_256;
    else static if (is(UT == ushort))
        alias maxmul10 = maxmul10_16;
    else static if (is(UT == ubyte))
        alias maxmul10 = maxmul10_8;
    else
        static assert(0);
}

//true on inexact
bool sqrt(U)(ref U x)
if (isAnyUnsignedBit!U)
{
    // Newton-Raphson: x = (x + n/x) / 2;
    //x
    if (x <= 1U)
        return false;
    const n = x;
    //1 ..          99   1 x 10^0 .. 99 x 10^0         1 .. 2  //0 - 10^0  <10^1      2 x 10^0, 6x10^0
    //100 ..      9999   1 x 10^2 ...99.99 x 10^2      3 .. 4  //2  -10^1  <10^3      2 x 10^1, 6x10^1
    //10000 ..  999999   1.x 10^4 ...99999.99 x 10^4   5 .. 6  //4  -10^2  <10^5      2 x 10^2, 6x10^2
    const p = prec(x);
    const int power = p & 1 ? p - 1 : p - 2;

    if (power >= pow10!U.length - 1 || x >= pow10!U[power + 1])
        x = pow10!U[power >> 1] * 6U;
    else
        x = pow10!U[power >> 1] << 1;  //* 2U;

    Unqual!U y;
    do
    {
        y = x;
        x = (x + n / x) >> 1;
    }
    while (x != y);
    return x * x != n;
}

//true on inexact
bool cbrt(U)(ref U x)
if (isAnyUnsignedBit!U)
{
    // Newton-Raphson: x = (2x + N/x2)/3
    if (x <= 1U)
        return false;
    const n = x;
    //1 ..          99   1 x 10^0 .. 99 x 10^0         1 .. 2  //0 - 10^0  <10^1      2 x 10^0, 6x10^0
    //100 ..      9999   1 x 10^2 ...99.99 x 10^2      3 .. 4  //2  -10^1  <10^3      2 x 10^1, 6x10^1
    //10000 ..  999999   1.x 10^4 ...99999.99 x 10^4   5 .. 6  //4  -10^2  <10^5      2 x 10^2, 6x10^2

    x /= 3U;
    if (!x)
        return true;

    Unqual!U y;
    do
    {
        y = x;
        x = ((x << 1) + n / (x * x)) / 3U;
    }
    while (x != y && x);
    return x * x * x != n;
}

U uparse(U)(const(char)[] s, ref bool overflow)
in
{
    assert(s.length, "Empty string");
    assert(!isHexString(s) || s.length > 2, "Empty hexadecimal string");
}
do
{
    Unqual!U result;
    size_t i = 0;
    if (isHexString(s))
    {
        i += 2;
        while (i < s.length && (s[i] == '0' || s[i] == '_'))
            ++i;
        int width = 0;
        enum maxWidth = U.sizeof * 8;
        while (i < s.length)
        {
            if (width >= maxWidth)
            {
                overflow = true;
                return result;
            }

            const char c = s[i++];
            if (c >= '0' && c <= '9')
            {
                result <<= 4;
                result |= cast(uint)(c - '0');
                width += 4;
            }
            else if (c >= 'A' && c <= 'F')
            {
                result <<= 4;
                result |= cast(uint)(c - 'A' + 10);
                width += 4;
            }
            else if (c >= 'a' && c <= 'f')
            {
                result <<= 4;
                result |= cast(uint)(c - 'a' + 10);
                width += 4;
            }
            else
                assert(c == '_', s); //"Invalid character in input string"
        }
    }
    else
    {
        while (i < s.length)
        {
            const char c = s[i++];
            if (c >= '0' && c <= '9')
            {
                auto r = fma(result, 10U, cast(uint)(c - '0'), overflow);
                if (overflow)
                    return result;
                result = r;
            }
            else
                assert(c == '_', s); //"Invalid character in input string"
        }
    }

    return result;
}

unittest // uparse
{
    bool overflow;
    uint512 x0 = uparse!uint512("0", overflow); assert(!overflow);
    uint512 x1 = uparse!uint512("1_234_567_890_123_456_789_012_345_678_901_234_567_890", overflow); assert(!overflow);
    uint512 x2 = uparse!uint512("0x1234_5678_9012_3456_7890_1234_5678_9012_3456_7890", overflow); assert(!overflow);
}

unittest // unUnsign
{
    bool overflow;
    assert(toUnsign!uint("0", overflow) == 0U); assert(!overflow);
    assert(toUnsign!uint("12_345", overflow) == 12_345U); assert(!overflow);
    assert(toUnsign!uint("0x1_2345", overflow) == 0x1_2345); assert(!overflow);
    assert(toUnsign!ulong("123_456_789_012", overflow) == 123_456_789_012LU); assert(!overflow);
    assert(toUnsign!ulong("0x1234_5678_9012", overflow) == 0x1234_5678_9012); assert(!overflow);
}

version(ShowEnumDecBytes) version(none)
unittest
{
    import std.stdio;
    scope (failure) assert(0, "Assume nothrow failed");

    ubyte[64] b512;

    foreach (i, ref n; pow10_512)
    {
        const b = n.toBigEndianBytes(b512[]);
        writeln("pow10_512[", i, "]: ", b);
    }
    writeln("");

    foreach (i, ref n; pow10RoundEven_512)
    {
        const b = n.toBigEndianBytes(b512[]);
        writeln("pow10RoundEven_512[", i, "]: ", b);
    }
    writeln("");

    // 256 bits
    ubyte[32] b256;

    foreach (i, ref n; pow10RoundEven_256)
    {
        const b = n.toBigEndianBytes(b256[]);
        writeln("pow10RoundEven_256[", i, "]: ", b);
    }
    writeln("");

    foreach (i, ref n; pow10_256)
    {
        const b = n.toBigEndianBytes(b256[]);
        writeln("pow10_256[", i, "]: ", b);
    }
    writeln("");

    foreach (i, ref n; maxmul10_256)
    {
        const b = n.toBigEndianBytes(b256[]);
        writeln("maxmul10_256[", i, "]: ", b);
    }
    writeln("");

    // 128 bits
    ubyte[16] b128;

    foreach (i, ref n; pow10_128)
    {
        const b = n.toBigEndianBytes(b128[]);
        writeln("pow10_128[", i, "]: ", b);
    }
    writeln("");

    foreach (i, ref n; pow10RoundEven_128)
    {
        const b = n.toBigEndianBytes(b128[]);
        writeln("pow10RoundEven_128[", i, "]: ", b);
    }
    writeln("");

    foreach (i, ref n; maxmul10_128)
    {
        const b = n.toBigEndianBytes(b128[]);
        writeln("maxmul10_128[", i, "]: ", b);
    }
}
