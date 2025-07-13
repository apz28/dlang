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

module pham.cp.cp_cipher_pem;

import std.algorithm.searching : endsWith, startsWith;

debug(debug_pham_cp_cp_cipher_pem) import std.stdio : writeln;
import pham.utl.utl_convert : bytesFromBase64s;
import pham.cp.cp_cipher : CipherKey, CipherPrivateRSAKey, CipherPublicRSAKey;

struct PemReader(alias pkcs8)
{
    import std.bitmanip : peek;
    import std.system : Endian;

nothrow pure @safe:

public:
    bool readAdvance(const(ushort) n1, const(ushort) n2)
    {
        const c = readUShort();
        if (c == n1)
            readByte();
        else if (c == n2)
            readBytes(2);
        else
            return false;
        return !empty;
    }

    ubyte readByte()
    {
        return !empty ? pkcs8[p++] : 0;
    }

    const(ubyte)[] readBytes(const(size_t) length) return
    {
        if (empty(length))
            return failedBytes();
        else
        {
            const c = p;
            p += length;
            return pkcs8[c..p];
        }
    }

    int readFieldLength()
    {
        if (empty)
            return failedSize();

        const firstByte = readByte();

        //when the value is less than 0x80, then it is a direct length.
        if (firstByte < 0x80)
            return firstByte;

        // When 0x8? is specified, the value after the 8 is the number of bytes to read for the length
        // we are going to assume up to 4 bytes since anything bigger is ridiculous, and 4 translates nicely to an integer
        // asn.1 is big endian, so just fill the array backwards.
        const bytesToRead = firstByte & 0x0F;
        ubyte[4] bytes;
        foreach (i; 0..bytesToRead)
        {
            if (empty)
                return -1;

            if (i < 4)
                bytes[i] = readByte();
            else
                readByte();
        }

        debug(debug_pham_cp_cp_cipher_pem) debug writeln(__FUNCTION__, "() - bytesToRead=", bytesToRead, ", bytes=", bytes[].dgToHex);
        
        return peek!(int, Endian.littleEndian)(bytes[]);
    }

    int readIntegerSize()
    {
        // expect integer type
        if (readByte() != 0x02)
            return failedSize();

        int result = readFieldLength();

        debug(debug_pham_cp_cp_cipher_pem) debug writeln(__FUNCTION__, "() - result=", result);
        
        return result;
    }

    const(ubyte)[] readKey(const(ubyte) n) return
    {
        // expect integer type
        if (readByte() != 0x02)
            return failedBytes();

        int elems;
        if (n == 1)
            elems = readByte();
        else
        {
            assert(n == 2);

            ubyte lowByte, highByte;
            const bytes = readByte();
            if (bytes == 0x81)
                lowByte = readByte();
            else if (bytes == 0x82)
            {
                highByte = readByte();
                lowByte = readByte();
            }
            else
                return failedBytes();

            elems = peek!(int, Endian.littleEndian)(cast(const(ubyte)[])[lowByte, highByte, 0x00, 0x00]);
        }
        
        debug(debug_pham_cp_cp_cipher_pem) debug writeln(__FUNCTION__, "() - elems=", elems, ", length=", length);
        
        return elems > 0 ? readBytes(elems) : null;
    }

    ushort readUShort()
    {
        if (empty(2))
            return cast(ushort)failedSize();

        ubyte[2] bytes;
        bytes[0] = readByte();
        bytes[1] = readByte();
        return peek!(ushort, Endian.littleEndian)(bytes[]);
    }

    pragma(inline, true)
    @property bool empty() const
    {
        return p >= pkcs8.length;
    }

    pragma(inline, true)
    @property bool empty(const(size_t) length) const
    {
        return p + length >= pkcs8.length;
    }

    @property size_t length() const
    {
        return pkcs8.length - p;
    }

    @property size_t position() const
    {
        return p;
    }

private:
    int failedSize()
    {
        p = pkcs8.length;
        return 0;
    }

    ubyte[] failedBytes()
    {
        p = pkcs8.length;
        return null;
    }

private:
    size_t p;
}

CipherKey pkcs8ParseRSAPrivateKey(scope const(ubyte)[] pkcs8)
{
    auto reader = PemReader!(pkcs8)();
    if (reader.empty)
        return CipherKey.init;

    // data read as little endian order (actual data order for Sequence is 30 81)
    const endianHeader = reader.readUShort();
    if (endianHeader == 0x8130)
        reader.readByte(); // advance 1 byte
    else if (endianHeader == 0x8230)
        reader.readBytes(2); // advance 2 bytes
    else
        return CipherKey.init;

    // version number
    if (reader.readUShort() != 0x0102)
        return CipherKey.init;

    if (reader.readByte() != 0x00)
        return CipherKey.init;

    // All private key components are Integer sequences

    const modulus = reader.readKey(2);
    const exponent = reader.readKey(1);
    const d = reader.readKey(2);
    const p = reader.readKey(2);
    const q = reader.readKey(2);
    const dp = reader.readKey(2);
    const dq = reader.readKey(2);
    const inversedq = reader.readKey(2);

    auto k = CipherPrivateRSAKey(0, modulus.dup, exponent.dup, d.dup, p.dup, q.dup, dp.dup, dq.dup, inversedq.dup);
    return CipherKey(k);
}

CipherKey pkcs8ParsePrivateKey(scope const(ubyte)[] pkcs8)
{
    auto reader = PemReader!(pkcs8)();

    if (!reader.readAdvance(0x8130, 0x8230))
        return CipherKey.init;

    if (reader.readByte() != 0x02)
        return CipherKey.init;

    if (reader.readUShort() != 0x0001)
        return CipherKey.init;

    // make sure Sequence for OID is correct
    if (reader.readBytes(15) != rsaOidSequence)
        return CipherKey.init;

    // expect an Octet string
    if (reader.readByte() != 0x04)
        return CipherKey.init;

    // read next byte, or next 2 bytes is  0x81 or 0x82; otherwise bt is the byte count
    const bt = reader.readByte();
    if (bt == 0x81)
        reader.readByte();
    else if (bt == 0x82)
        reader.readBytes(2);

    // at this stage, the remaining sequence should be the RSA private key
    auto pkcs8RSA = reader.readBytes(reader.length);
    return pkcs8ParseRSAPrivateKey(pkcs8RSA);
}

CipherKey pemParsePrivateKey(scope const(char)[] pem)
{
    auto pkcs8RSA = pemExtractBytes(pem, pemRSAPrivateKeyHeader, pemRSAPrivateKeyFooter);
    scope (exit)
        pkcs8RSA[] = 0;
    if (pkcs8RSA.length)
        return pkcs8ParseRSAPrivateKey(pkcs8RSA);

    auto pkcs8 = pemExtractBytes(pem, pemPrivateKeyHeader, pemPrivateKeyFooter);
    scope (exit)
        pkcs8[] = 0;
    if (pkcs8.length)
        return pkcs8ParsePrivateKey(pkcs8);

    return CipherKey.init;
}

CipherKey pkcs8ParsePublicKey(scope const(ubyte)[] pkcs8)
{
    debug(debug_pham_cp_cp_cipher_pem) debug writeln(__FUNCTION__, "(pkcs8=", pkcs8.dgToHex(), ")");

    auto reader = PemReader!(pkcs8)();

    if (!reader.readAdvance(0x8130, 0x8230))
        return CipherKey.init;

    // make sure Sequence for OID is correct
    if (reader.readBytes(15) != rsaOidSequence)
        return CipherKey.init;

    if (!reader.readAdvance(0x8103, 0x8203))
        return CipherKey.init;

    // expect a zero for number of bits in the bitstring that are unused
    if (reader.readByte() != 0x00)
        return CipherKey.init;

    if (!reader.readAdvance(0x8130, 0x8230))
        return CipherKey.init;

    debug(debug_pham_cp_cp_cipher_pem) debug writeln("\t", "reader.empty=", reader.empty);
    
    const modulus = reader.readKey(2);
    const exponent = reader.readKey(1);

    debug(debug_pham_cp_cp_cipher_pem) debug writeln("\t", "modulus=", modulus.dgToHex(), ", exponent=", exponent.dgToHex());
    
    auto k = CipherPublicRSAKey(0, modulus.dup, exponent.dup);
    return CipherKey(k);
}

CipherKey pemParsePublicKey(scope const(char)[] pem)
{
    auto pkcs8 = pemExtractBytes(pem, pemPublicKeyHeader, pemPublicKeyFooter);
    scope (exit)
        pkcs8[] = 0;
    return pkcs8ParsePublicKey(pkcs8);
}

ubyte[] pemExtractBytes(scope const(char)[] pem, scope const(char)[] header, scope const(char)[] footer)
{
    // Trim
    size_t i = 0, j = pem.length;
    while (i < j && pem[i] <= ' ')
        i++;
    while (j > i && pem[j - 1] <= ' ')
        j--;
    if (i != 0 || j != pem.length)
        pem = pem[i..j];

    // Valid with markers?
    if (!pem.startsWith(header) || !pem.endsWith(footer))
        return null;

    // Base64 data
    pem = pem[header.length..pem.length - footer.length];
    return bytesFromBase64s(pem);
}

// 1.2.840.113549.1.1.1 - RSA encryption, including the sequence byte and terminal encoded null
static immutable ubyte[] rsaOidSequence = [0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00];
static immutable ubyte[] pkcs5PBES2OidSequence = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0D];
static immutable ubyte[] pkcs5PBKDF2OidSequence = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0C];
// 1.2.840.113549.3.7 - DES-EDE3-CBC
static immutable ubyte[] desEDE3CBCOidSequence = [0x06, 0x08, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x03, 0x07];

static immutable string pemPublicKeyHeader = "-----BEGIN PUBLIC KEY-----";
static immutable string pemPublicKeyFooter = "-----END PUBLIC KEY-----";

static immutable string pemRSAPrivateKeyHeader = "-----BEGIN RSA PRIVATE KEY-----";
static immutable string pemRSAPrivateKeyFooter = "-----END RSA PRIVATE KEY-----";
static immutable string pemPrivateKeyHeader = "-----BEGIN PRIVATE KEY-----";
static immutable string pemPrivateKeyFooter = "-----END PRIVATE KEY-----";
//static immutable string pemPrivateEncryptedKeyHeader = "-----BEGIN ENCRYPTED PRIVATE KEY-----";
//static immutable string pemPrivateEncryptedKeyFooter = "-----END ENCRYPTED PRIVATE KEY-----";


private:

unittest
{
    static immutable string publicPem =
q"PEM
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5RBVpeGMSit3ecM6CcU6
jdapaaXMKIkTPD5bhtYX/nZEP5WTorpKkgwcYHsqdoE8yrmYhARCtV0yFju+9SJ/
0eLvm5SbWaVO9fK0S3mqTdPCkRQquGXm7Euyz3tfG4t42qkYqEge1FpgiP9LiJDQ
KBZjhGPa8J0jorWBCeL6DrhVQd/RJhgkCa5CTxCWLrYgICxjXrmIJVXrgNuPgsMA
QnC8H8cIFmR6sKMV2AW9IWKzn1u9PwNCDCPZvGw5+0104N3yk/eJWv08X1uix1fT
KBkE8zqUfFN4IECtpNvHj7uxaOsWrRzh0XvwnjMCkEJfLigMO1ijgMVGvI890Ed1
9wIDAQAB
-----END PUBLIC KEY-----
PEM";

    auto cipherKey = pemParsePublicKey(publicPem);
    //dgWriteln("cipherKey.modulus=", cipherKey.modulus.dgToHex());
    //dgWriteln("cipherKey.exponent=", cipherKey.exponent.dgToHex());
}
