/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2021 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 */

module pham.cp.cipher_digest;

import std.algorithm.mutation : swapAt;
import std.digest.md : MD5Digest;
import std.digest.sha : Digest, SHA1Digest, SHA256Digest, SHA384Digest, SHA512Digest;
import std.string : representation;

import pham.utl.disposable : DisposingReason;

nothrow @safe:

enum DigestId : string
{
    md5 = "MD5",
    sha1 = "SHA1",
    sha256 = "SHA256",
    sha384 = "SHA384",
    sha512 = "SHA512",
}

struct DigestResult
{
@nogc nothrow @safe:

public:
    // bits / bits-per-byte * 2 hex-chars-per-byte
    enum maxBufferSize = (Digester.maxDigestLength * 2) + ulong.sizeof; // Allow extra for cipher salt calculation

public:
    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) opOpAssign(string op)(scope const(ubyte)[] rhs) pure return
    if (op == "&" || op == "|" || op == "^")
    {
        const len = length > rhs.length ? rhs.length : length;
        static if (op == "&")
        {
            foreach (i; 0..len)
                buffer[i] &= rhs[i];
            if (len < length)
                buffer[len..length] = 0;
            return this;
        }
        else static if (op == "|")
        {
            foreach (i; 0..len)
                buffer[i] |= rhs[i];
            return this;
        }
        else static if (op == "^")
        {
            foreach (i; 0..len)
                buffer[i] ^= rhs[i];
            return this;
        }
        else
            static assert(0);
    }

    size_t opDollar() const pure
    {
        return length;
    }

    inout(ubyte)[] opIndex() inout pure return
    {
        return buffer[0..length];
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        buffer[] = 0;
        length = 0;
    }

    ref typeof(this) reset() pure return
    {
        length = 0;
        return this;
    }

    ref typeof(this) reverse() pure return
    {
        if (const len = length)
        {
            const last = len - 1;
            const steps = len / 2;
            for (size_t i = 0; i < steps; i++)
            {
                buffer.swapAt(i, last - i);
            }
        }
        return this;
    }

    inout(ubyte)[] slice(uint beginIndex, uint forLength) inout pure return
    {
        return buffer[beginIndex..beginIndex + forLength];
    }

    @property bool empty() const pure
    {
        return length == 0;
    }

public:
    ubyte[maxBufferSize] buffer;
    size_t length;
}

struct Digester
{
nothrow @safe:

public:
    enum maxDigestLength = 512;

public:
    this(DigestId digestId)
    {
        this._digestId = digestId;
        final switch (digestId)
        {
            case DigestId.md5:
                enum md5Bits = 128;
                this._digestBits = md5Bits;
                this._digester = new MD5Digest();
                break;

            case DigestId.sha1:
                enum sha1Bits = 160;
                this._digestBits = sha1Bits;
                this._digester = new SHA1Digest();
                break;

            case DigestId.sha256:
                enum sha256Bits = 256;
                this._digestBits = sha256Bits;
                this._digester = new SHA256Digest();
                break;

            case DigestId.sha384:
                enum sha384Bits = 384;
                this._digestBits = sha384Bits;
                this._digester = new SHA384Digest();
                break;

            case DigestId.sha512:
                enum sha512Bits = 512;
                this._digestBits = sha512Bits;
                this._digester = new SHA512Digest();
                break;
        }
    }

    ref typeof(this) begin() return
    {
        _digester.reset();
        return this;
    }

    ref typeof(this) digest(scope const(ubyte)[] data...) return
    {
        foreach (d; data)
            _digester.put(d);
        return this;
    }

    ref typeof(this) digest(scope const(char)[] data) return
    {
        _digester.put(data.representation);
        return this;
    }

    ubyte[] finish(return ref DigestResult outBuffer) @trusted
    {
        outBuffer.length = digestLength;
        return _digester.finish(outBuffer.buffer[]);
    }

    @property uint digestBits() const @nogc pure
    {
        return _digestBits;
    }

    @property DigestId digestId() const pure
    {
        return _digestId;
    }

    @property uint digestLength() const @nogc pure
    {
        return (_digestBits + 7) / 8;
    }

private:
    DigestId _digestId;
    Digest _digester;
    uint _digestBits;
}

ubyte[] digestOf(DigestId id)(scope const(ubyte)[] data...)
{
    DigestResult rTemp = void;
    auto hasher = new Digester(id);
    return hasher.begin()
        .digest(data)
        .finish(rTemp)
        .dup;
}

struct HMACS
{
nothrow @safe:

public:
    this(DigestId digestId, scope const(ubyte)[] key)
    {
        this._digestId = digestId;
        this._blockSize = getBlockSize(digestId);
        this._hasher = Digester(digestId);
        // Must initialize _blockSize & _hasher before calling checkKey
        this._key = checkKey(key);
    }

    ~this() pure
    {
        dispose(DisposingReason.destructor);
    }

    ref typeof(this) begin() return
    {
        // Setup key pad
        foreach (i; 0..blockSize)
        {
            const k = _key[i];
            _iPad[i] = k ^ 0x36;
            _oPad[i] = k ^ 0x5C;
        }

        // Start with inner pad
        _hasher.begin().digest(_iPad[0..blockSize]);

        return this;
    }

    ref typeof(this) digest(scope const(ubyte)[] data...) return
    {
        _hasher.digest(data);
        return this;
    }

    ref typeof(this) digest(scope const(char)[] data) return
    {
        _hasher.digest(data);
        return this;
    }

    void dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    {
        _key[] = 0;
        _iPad[] = 0;
        _oPad[] = 0;
        _blockSize = 0;
    }

    ubyte[] finish(return ref DigestResult outBuffer)
    {
        DigestResult firstPassBuffer = void;
        const firstPass = _hasher.finish(firstPassBuffer);

        return _hasher.begin()
            .digest(_oPad[0..blockSize])
            .digest(firstPass)
            .finish(outBuffer);
    }

    @property uint blockSize() const pure
    {
        return _blockSize;
    }

    @property DigestId digestId() const pure
    {
        return _digestId;
    }

private:
    ubyte[maxBlockSize] checkKey(scope const(ubyte)[] key)
    in
    {
        assert(blockSize > 0);
        assert(maxBlockSize >= blockSize);
    }
    do
    {
        ubyte[maxBlockSize] result = 0;
        if (key.length <= blockSize)
            result[0..key.length] = key[0..key.length];
        else
        {
            DigestResult rTemp = void;
            auto r = this._hasher.begin()
                .digest(key)
                .finish(rTemp);
            result[0..r.length] = r[0..r.length];
        }
        return result;
    }

    static uint getBlockSize(DigestId digestId) pure
    {
        final switch (digestId)
        {
            case DigestId.md5: return 64;
            case DigestId.sha1: return 64;
            case DigestId.sha256: return 64;
            case DigestId.sha384: return 128;
            case DigestId.sha512: return 128;
        }
    }

    enum maxBlockSize = 128;

private:
    DigestId _digestId;
    Digester _hasher;
    ubyte[maxBlockSize] _key, _iPad, _oPad;
    uint _blockSize;
}


private:

nothrow @safe unittest // digestOf
{
    import std.string : representation;
    import pham.utl.object;
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.cipher_digest.digestOf");

    ubyte[] hash;

    hash = digestOf!(DigestId.md5)("abc".representation);
    assert(bytesToHexs(hash) == "900150983CD24FB0D6963F7D28E17F72");

    hash = digestOf!(DigestId.sha1)("abc".representation);
    assert(bytesToHexs(hash) == "A9993E364706816ABA3E25717850C26C9CD0D89D");

    hash = digestOf!(DigestId.sha256)("message digest".representation);
    assert(hash == bytesFromHexs("f7846f55cf23e14eebeab5b4e1550cad5b509e3348fbc4efa3a1413d393cb650"));

    hash = digestOf!(DigestId.sha384)("message digest".representation);
    assert(hash == bytesFromHexs("473ed35167ec1f5d8e550368a3db39be54639f828868e9454c239fc8b52e3c61dbd0d8b4de1390c256dcbb5d5fd99cd5"));

    hash = digestOf!(DigestId.sha512)("message digest".representation);
    assert(hash == bytesFromHexs("107dbf389d9e9f71a3a95f6c055b9251bc5268c2be16d6c13492ea45b0199f3309e16455ab1e96118e8a905d5597b72038ddb372a89826046de66687bb420e7c"));
}

nothrow @safe unittest // digestOf - for Firebird database engine
{
    import std.string : representation;
    import pham.utl.object;
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.cipher_digest.digestOf - for Firebird database engine");

    ubyte[] hash;

    hash = digestOf!(DigestId.sha1)("SYSDBA:masterkey".representation);
    assert(hash == bytesFromHexs("E395799C5652AAA4536273A20AA740E246835CC4"));

    hash = digestOf!(DigestId.sha1)("DAVIDS:aaa123".representation);
    assert(hash == bytesFromHexs("DF2ACDCF3828998D9ED023AB1F54464220F0D17C"));
}

nothrow @safe unittest // HMACS
{
    import std.string : representation;
    import pham.utl.object;
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.cipher_digest.HMACS");

    DigestResult rBuffer = void;
    ubyte[] r;

    // MD5
    auto hmacsMD5 = HMACS(DigestId.md5, "key".representation);
    r = hmacsMD5.begin()
        .digest("The quick brown fox jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("80070713463e7749b90c2dc24911e275"));

    r = hmacsMD5.begin()
        .digest("The quick brown fox ".representation)
        .digest("jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("80070713463e7749b90c2dc24911e275"));

    hmacsMD5 = HMACS(DigestId.md5, "012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789".representation);
    r = hmacsMD5.begin()
        .digest("The quick brown fox jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("e1728d68e05beae186ea768561963778"));

    // SHA1
    auto hmacsSHA1 = HMACS(DigestId.sha1, "key".representation);
    r = hmacsSHA1.begin()
        .digest("The quick brown fox jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9"));

    r = hmacsSHA1.begin()
        .digest("The quick brown fox ".representation)
        .digest("jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9"));

    hmacsSHA1 = HMACS(DigestId.sha1, "012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789".representation);
    r = hmacsSHA1.begin()
        .digest("The quick brown fox jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("560d3cd77316e57ab4bba0c186966200d2b37ba3"));

    // SHA256
    auto hmacsSHA256 = HMACS(DigestId.sha256, "key".representation);
    r = hmacsSHA256.begin()
        .digest("The quick brown fox jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"));

    r = hmacsSHA256.begin()
        .digest("The quick brown fox ".representation)
        .digest("jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"));

    hmacsSHA256 = HMACS(DigestId.sha256, "012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789".representation);
    r = hmacsSHA256.begin()
        .digest("The quick brown fox jumps over the lazy dog".representation)
        .finish(rBuffer);
    assert(r == bytesFromHexs("a1b0065a5d1edd93152c677e1bc1b1e3bc70d3a76619842e7f733f02b8135c04"));
}
