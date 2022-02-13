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

module pham.cp.codec_asn1;

import std.traits : isIntegral, Unqual;

import pham.utl.big_integer : BigInteger;
import pham.cp.cipher : CipherBuffer;

nothrow @safe:

/**
 * ASN.1 Class Tags
 */
enum ASN1Class : ubyte
{
	universal       = 0,
	application     = 1,
	contextSpecific = 2,
	private_        = 3,
}

/**
 * ASN.1 Type Tags
 */
enum ASN1Tag : ubyte
{
    eoc                  = 0x00,
    boolean              = 0x01,
    integer              = 0x02,
    bitString            = 0x03,
    octetString          = 0x04,
    null_                = 0x05,
    oid                  = 0x06,
    float_               = 0x09,
    enum_                = 0x0A,
    time                 = 0x0E,
    utf8String           = 0x0C,
    sequence             = 0x10,
    set                  = 0x11,
    numericString        = 0x12,
    printableString      = 0x13,
    t61String            = 0x14,
    iA5String            = 0x16,
    utcTime              = 0x17,
    generalizedTime      = 0x18,
    generalString        = 0x1B,
    //visibleString        = 0x1A,
    bmpString            = 0x1E,
    date                 = 0x1F,
    dateTime             = 0x21,
    duration             = 0x22,
}

// Returns the bit-length of bitString by considering the
// most-significant bit in a byte to be the "first" bit. This convention
// matches ASN.1, but differs from almost everything else.
size_t calBitLength(scope const(ubyte)[] x) @nogc pure
{
	size_t result = x.length * 8;
    foreach (i; 0..x.length)
	{
		const b = x[x.length - i - 1];
		foreach (bit; 0..8)
        {
			if (((b>>bit)&1) == 1)
				return result;
			result--;
		}
	}
	return 0;
}

class ASN1OId
{
nothrow @safe:

public:
    this(string id, string name) pure
    {
        this._id = id;
        this._name = name;
    }

    static ASN1OId add(string id, string name) @trusted
    in
    {
        assert(id.length != 0);
        assert(name.length != 0);
    }
    do
    {
        auto oid = new ASN1OId(id, name);
        _idMaps[oid.id] = oid;
        _nameMaps[oid.name] = oid;
        return oid;
    }

    static ASN1OId idOf(scope const(char)[] id) @trusted
    {
        if (auto e = id in _idMaps)
            return *e;
        else
            return null;
    }

    static ASN1OId nameOf(scope const(char)[] name) @trusted
    {
        if (auto e = name in _nameMaps)
            return *e;
        else
            return null;
    }

    @property string id() const pure @nogc
    {
        return _id;
    }

    @property string name() const pure @nogc
    {
        return _name;
    }

private:
    static void initializeDefaults()
    {
        /* Public key types */
        add("2.5.8.1.1", "RSA"); // RSA alternate
        add("1.2.840.10040.4.1", "DSA");
        add("1.2.840.10046.2.1", "DH");
        add("1.3.6.1.4.1.3029.1.2.1", "ElGamal");
        add("1.3.6.1.4.1.25258.1.1", "RW");
        add("1.3.6.1.4.1.25258.1.2", "NR");
		add("1.3.6.1.4.1.25258.1.4", "Curve25519");
		add("1.3.6.1.4.1.11591.15.1", "Curve25519");

        // X9.62 ecPublicKey, valid for ECDSA and ECDH (RFC 3279 sec 2.3.5)
        add("1.2.840.10045.2.1", "ECDSA");

        /*
        * This is an OID defined for ECDH keys though rarely used for such.
        * In this configuration it is accepted on decoding, but not used for
        * encoding. You can enable it for encoding by calling
        * ASN1OId.add("ECDH", "1.3.132.1.12")
        * from your application code.
        */
        add("1.3.132.1.12", "ECDH");

        add("1.2.643.2.2.19", "GOST-34.10"); // RFC 4491

        /* Ciphers */
        add("1.3.14.3.2.7", "DES/CBC");
        add("1.2.840.113549.3.7", "TripleDES/CBC");
        add("1.2.840.113549.3.2", "RC2/CBC");
        add("1.2.840.113533.7.66.10", "CAST-128/CBC");
        add("2.16.840.1.101.3.4.1.2", "AES-128/CBC");
        add("2.16.840.1.101.3.4.1.22", "AES-192/CBC");
        add("2.16.840.1.101.3.4.1.42", "AES-256/CBC");
        add("1.2.410.200004.1.4", "SEED/CBC"); // RFC 4010
        add("1.3.6.1.4.1.25258.3.1", "Serpent/CBC");
		add("1.3.6.1.4.1.25258.3.2", "Threefish-512/CBC");
		add("1.3.6.1.4.1.25258.3.3", "Twofish/CBC");
		add("2.16.840.1.101.3.4.1.6", "AES-128/GCM");
		add("2.16.840.1.101.3.4.1.26", "AES-192/GCM");
		add("2.16.840.1.101.3.4.1.46", "AES-256/GCM");
		add("1.3.6.1.4.1.25258.3.101", "Serpent/GCM");
		add("1.3.6.1.4.1.25258.3.102", "Twofish/GCM");
		add("1.3.6.1.4.1.25258.3.2.1", "AES-128/OCB");
		add("1.3.6.1.4.1.25258.3.2.2", "AES-192/OCB");
		add("1.3.6.1.4.1.25258.3.2.3", "AES-256/OCB");
		add("1.3.6.1.4.1.25258.3.2.4", "Serpent/OCB");
		add("1.3.6.1.4.1.25258.3.2.5", "Twofish/OCB");

		/* Hash Functions */
        add("1.2.840.113549.2.5", "MD5");
        add("1.3.6.1.4.1.11591.12.2", "Tiger(24,3)");

        add("1.3.14.3.2.26", "SHA-160");
        add("2.16.840.1.101.3.4.2.4", "SHA-224");
        add("2.16.840.1.101.3.4.2.1", "SHA-256");
        add("2.16.840.1.101.3.4.2.2", "SHA-384");
        add("2.16.840.1.101.3.4.2.3", "SHA-512");

        /* MACs */
        add("1.2.840.113549.2.7", "HMAC(SHA-160)");
        add("1.2.840.113549.2.8", "HMAC(SHA-224)");
        add("1.2.840.113549.2.9", "HMAC(SHA-256)");
        add("1.2.840.113549.2.10", "HMAC(SHA-384)");
        add("1.2.840.113549.2.11", "HMAC(SHA-512)");

        /* Key Wrap */
        add("1.2.840.113549.1.9.16.3.6", "KeyWrap.TripleDES");
        add("1.2.840.113549.1.9.16.3.7", "KeyWrap.RC2");
        add("1.2.840.113533.7.66.15", "KeyWrap.CAST-128");
        add("2.16.840.1.101.3.4.1.5", "KeyWrap.AES-128");
        add("2.16.840.1.101.3.4.1.25", "KeyWrap.AES-192");
        add("2.16.840.1.101.3.4.1.45", "KeyWrap.AES-256");

        /* Compression */
        add("1.2.840.113549.1.9.16.3.8", "Compression.Zlib");

        /* Public key signature schemes */
        add("1.2.840.113549.1.1.1", "RSA/EME-PKCS1-v1_5");
        add("1.2.840.113549.1.1.2", "RSA/EMSA3(MD2)");
        add("1.2.840.113549.1.1.4", "RSA/EMSA3(MD5)");
        add("1.2.840.113549.1.1.5", "RSA/EMSA3(SHA-160)");
        add("1.2.840.113549.1.1.11", "RSA/EMSA3(SHA-256)");
        add("1.2.840.113549.1.1.12", "RSA/EMSA3(SHA-384)");
        add("1.2.840.113549.1.1.13", "RSA/EMSA3(SHA-512)");
        add("1.3.36.3.3.1.2", "RSA/EMSA3(RIPEMD-160)");

        add("1.2.840.10040.4.3", "DSA/EMSA1(SHA-160)");
        add("2.16.840.1.101.3.4.3.1", "DSA/EMSA1(SHA-224)");
        add("2.16.840.1.101.3.4.3.2", "DSA/EMSA1(SHA-256)");

        add("0.4.0.127.0.7.1.1.4.1.1", "ECDSA/EMSA1_BSI(SHA-160)");
        add("0.4.0.127.0.7.1.1.4.1.2", "ECDSA/EMSA1_BSI(SHA-224)");
        add("0.4.0.127.0.7.1.1.4.1.3", "ECDSA/EMSA1_BSI(SHA-256)");
        add("0.4.0.127.0.7.1.1.4.1.4", "ECDSA/EMSA1_BSI(SHA-384)");
        add("0.4.0.127.0.7.1.1.4.1.5", "ECDSA/EMSA1_BSI(SHA-512)");
        add("0.4.0.127.0.7.1.1.4.1.6", "ECDSA/EMSA1_BSI(RIPEMD-160)");

        add("1.2.840.10045.4.1", "ECDSA/EMSA1(SHA-160)");
        add("1.2.840.10045.4.3.1", "ECDSA/EMSA1(SHA-224)");
        add("1.2.840.10045.4.3.2", "ECDSA/EMSA1(SHA-256)");
        add("1.2.840.10045.4.3.3", "ECDSA/EMSA1(SHA-384)");
        add("1.2.840.10045.4.3.4", "ECDSA/EMSA1(SHA-512)");

        add("1.2.643.2.2.3", "GOST-34.10/EMSA1(GOST-R-34.11-94)");

        add("1.3.6.1.4.1.25258.2.1.1.1", "RW/EMSA2(RIPEMD-160)");
        add("1.3.6.1.4.1.25258.2.1.1.2", "RW/EMSA2(SHA-160)");
        add("1.3.6.1.4.1.25258.2.1.1.3", "RW/EMSA2(SHA-224)");
        add("1.3.6.1.4.1.25258.2.1.1.4", "RW/EMSA2(SHA-256)");
        add("1.3.6.1.4.1.25258.2.1.1.5", "RW/EMSA2(SHA-384)");
        add("1.3.6.1.4.1.25258.2.1.1.6", "RW/EMSA2(SHA-512)");

        add("1.3.6.1.4.1.25258.2.1.2.1", "RW/EMSA4(RIPEMD-160)");
        add("1.3.6.1.4.1.25258.2.1.2.2", "RW/EMSA4(SHA-160)");
        add("1.3.6.1.4.1.25258.2.1.2.3", "RW/EMSA4(SHA-224)");
        add("1.3.6.1.4.1.25258.2.1.2.4", "RW/EMSA4(SHA-256)");
        add("1.3.6.1.4.1.25258.2.1.2.5", "RW/EMSA4(SHA-384)");
        add("1.3.6.1.4.1.25258.2.1.2.6", "RW/EMSA4(SHA-512)");

        add("1.3.6.1.4.1.25258.2.2.1.1", "NR/EMSA2(RIPEMD-160)");
        add("1.3.6.1.4.1.25258.2.2.1.2", "NR/EMSA2(SHA-160)");
        add("1.3.6.1.4.1.25258.2.2.1.3", "NR/EMSA2(SHA-224)");
        add("1.3.6.1.4.1.25258.2.2.1.4", "NR/EMSA2(SHA-256)");
        add("1.3.6.1.4.1.25258.2.2.1.5", "NR/EMSA2(SHA-384)");
        add("1.3.6.1.4.1.25258.2.2.1.6", "NR/EMSA2(SHA-512)");

        add("2.5.4.3",  "X520.CommonName");
        add("2.5.4.4",  "X520.Surname");
        add("2.5.4.5",  "X520.SerialNumber");
        add("2.5.4.6",  "X520.Country");
        add("2.5.4.7",  "X520.Locality");
        add("2.5.4.8",  "X520.State");
        add("2.5.4.10", "X520.Organization");
        add("2.5.4.11", "X520.OrganizationalUnit");
        add("2.5.4.12", "X520.Title");
        add("2.5.4.42", "X520.GivenName");
        add("2.5.4.43", "X520.Initials");
        add("2.5.4.44", "X520.GenerationalQualifier");
        add("2.5.4.46", "X520.DNQualifier");
        add("2.5.4.65", "X520.Pseudonym");

        add("1.2.840.113549.1.5.12", "PKCS5.PBKDF2");
        add("1.2.840.113549.1.5.13", "PBE-PKCS5v20");

        add("1.2.840.113549.1.9.1", "PKCS9.EmailAddress");
        add("1.2.840.113549.1.9.2", "PKCS9.UnstructuredName");
        add("1.2.840.113549.1.9.3", "PKCS9.ContentType");
        add("1.2.840.113549.1.9.4", "PKCS9.MessageDigest");
        add("1.2.840.113549.1.9.7", "PKCS9.ChallengePassword");
        add("1.2.840.113549.1.9.14", "PKCS9.ExtensionRequest");

        add("1.2.840.113549.1.7.1", "CMS.DataContent");
        add("1.2.840.113549.1.7.2", "CMS.SignedData");
        add("1.2.840.113549.1.7.3", "CMS.EnvelopedData");
        add("1.2.840.113549.1.7.5", "CMS.DigestedData");
        add("1.2.840.113549.1.7.6", "CMS.EncryptedData");
        add("1.2.840.113549.1.9.16.1.2", "CMS.AuthenticatedData");
        add("1.2.840.113549.1.9.16.1.9", "CMS.CompressedData");

        add("2.5.29.14", "X509v3.SubjectKeyIdentifier");
        add("2.5.29.15", "X509v3.KeyUsage");
        add("2.5.29.17", "X509v3.SubjectAlternativeName");
        add("2.5.29.18", "X509v3.IssuerAlternativeName");
        add("2.5.29.19", "X509v3.BasicConstraints");
        add("2.5.29.20", "X509v3.CRLNumber");
        add("2.5.29.21", "X509v3.ReasonCode");
        add("2.5.29.23", "X509v3.HoldInstructionCode");
        add("2.5.29.24", "X509v3.InvalidityDate");
        add("2.5.29.31", "X509v3.CRLDistributionPoints");
        add("2.5.29.32", "X509v3.CertificatePolicies");
        add("2.5.29.35", "X509v3.AuthorityKeyIdentifier");
        add("2.5.29.36", "X509v3.PolicyConstraints");
        add("2.5.29.37", "X509v3.ExtendedKeyUsage");
        add("1.3.6.1.5.5.7.1.1", "PKIX.AuthorityInformationAccess");

        add("2.5.29.32.0", "X509v3.AnyPolicy");

        add("1.3.6.1.5.5.7.3.1", "PKIX.ServerAuth");
        add("1.3.6.1.5.5.7.3.2", "PKIX.ClientAuth");
        add("1.3.6.1.5.5.7.3.3", "PKIX.CodeSigning");
        add("1.3.6.1.5.5.7.3.4", "PKIX.EmailProtection");
        add("1.3.6.1.5.5.7.3.5", "PKIX.IPsecEndSystem");
        add("1.3.6.1.5.5.7.3.6", "PKIX.IPsecTunnel");
        add("1.3.6.1.5.5.7.3.7", "PKIX.IPsecUser");
        add("1.3.6.1.5.5.7.3.8", "PKIX.TimeStamping");
        add("1.3.6.1.5.5.7.3.9", "PKIX.OCSPSigning");

        add("1.3.6.1.5.5.7.8.5", "PKIX.XMPPAddr");

        add("1.3.6.1.5.5.7.48.1", "PKIX.OCSP");
        add("1.3.6.1.5.5.7.48.1.1", "PKIX.OCSP.BasicResponse");

        /* ECC domain parameters */
        add("1.3.132.0.6",  "secp112r1");
        add("1.3.132.0.7",  "secp112r2");
        add("1.3.132.0.8",  "secp160r1");
        add("1.3.132.0.9",  "secp160k1");
        add("1.3.132.0.10", "secp256k1");
        add("1.3.132.0.28", "secp128r1");
        add("1.3.132.0.29", "secp128r2");
        add("1.3.132.0.30", "secp160r2");
        add("1.3.132.0.31", "secp192k1");
        add("1.3.132.0.32", "secp224k1");
        add("1.3.132.0.33", "secp224r1");
        add("1.3.132.0.34", "secp384r1");
        add("1.3.132.0.35", "secp521r1");

        add("1.2.840.10045.3.1.1", "secp192r1");
        add("1.2.840.10045.3.1.2", "x962_p192v2");
        add("1.2.840.10045.3.1.3", "x962_p192v3");
        add("1.2.840.10045.3.1.4", "x962_p239v1");
        add("1.2.840.10045.3.1.5", "x962_p239v2");
        add("1.2.840.10045.3.1.6", "x962_p239v3");
        add("1.2.840.10045.3.1.7", "secp256r1");

        add("1.3.36.3.3.2.8.1.1.1", "brainpool160r1");
        add("1.3.36.3.3.2.8.1.1.3", "brainpool192r1");
        add("1.3.36.3.3.2.8.1.1.5", "brainpool224r1");
        add("1.3.36.3.3.2.8.1.1.7", "brainpool256r1");
        add("1.3.36.3.3.2.8.1.1.9", "brainpool320r1");
        add("1.3.36.3.3.2.8.1.1.11", "brainpool384r1");
        add("1.3.36.3.3.2.8.1.1.13", "brainpool512r1");

        add("1.2.643.2.2.35.1", "gost_256A");
        add("1.2.643.2.2.36.0", "gost_256A");

        /* CVC */
        add("0.4.0.127.0.7.3.1.2.1", "CertificateHolderAuthorizationTemplate");
    }

private:
    string _id;
    string _name;

    __gshared static ASN1OId[string] _idMaps, _nameMaps;
}

struct ASN1BitString
{
nothrow @safe:

public:
    this(ubyte[] bytes) pure
    {
        this._bytes = bytes;
        this._bitLength = calBitLength(bytes);
    }

    // RightAlign returns a slice where the padding bits are at the beginning. The
    // slice may share memory with the BitString.
    const(ubyte)[] rightAlign() const pure
    {
	    const shift = 8 - (bitLength % 8);
	    if (shift == 8 || _bytes.length == 0)
		    return _bytes;

    	ubyte[] result = new ubyte[](_bytes.length);
	    result[0] = _bytes[0] >> shift;
	    foreach (i; 1.._bytes.length)
        {
		    result[i] = cast(ubyte)(_bytes[i-1] << (8 - shift));
		    result[i] |= _bytes[i] >> shift;
	    }
	    return result;
    }

    @property const(ubyte)[] bytes() const pure
    {
        return _bytes;
    }

    @property size_t bitLength() const @nogc pure
    {
        return _bitLength;
    }

private:
    ubyte[] _bytes;
    size_t _bitLength;
}

struct ASN1BerDecoder
{

}

struct ASN1DerEncoder
{
nothrow @safe:

public:
    static ubyte lengthBase128Int64(long x) @nogc pure
    {
	    if (x == 0)
		    return 1;

	    ubyte result = 0;
        while (x > 0)
        {
            result++;
            x >>= 7;
        }

	    return result;
    }

    static size_t lengthBitString(scope const(ubyte)[] x) @nogc pure
    {
        return x.length + 1;
    }

    static ubyte lengthIntegral(T)(const(T) x) @nogc pure
    if (isIntegral!T)
    {
        Unqual!T ux = x;

	    ubyte result = 1;

	    while (ux > 127)
        {
		    result++;
		    ux >>= 8;
	    }

        static if (isSigned!T)
	    while (ux < -128)
        {
		    result++;
		    ux >>= 8;
	    }

	    return result;
    }

    static ubyte lengthLength(size_t n) @nogc pure
    {
        ubyte result = 1;
	    while (n > 255)
        {
		    result++;
		    n >>= 8;
	    }
        return result;
    }

    static void  writeBase128Int64(ref CipherBuffer destination, long x)
    {
	    const n = lengthBase128Int64(x);
	    for (int i = n - 1; i >= 0; i--)
        {
		    ubyte b = cast(ubyte)((x >> (i*7)) & 0x7F);
		    if (i != 0)
			    b |= 0x80;
            destination.put(b);
    	}
    }

    static void writeIntegral(T)(ref CipherBuffer destination, const(T) x) pure
    if (isIntegral!T)
    {
	    const n = x.lengthIntegral();
	    foreach (j; 0..n)
		    destination.put(cast(ubyte)(x >> ((n - 1 - j) * 8)));
    }

    static void writeLength(ref CipherBuffer destination, size_t n) pure
    {
        if (n >= 128)
        {
		    const count = lengthLength(n);
            destination.put(cast(ubyte)(0x80 | count));
            foreach (i; 0..count)
                destination.put(cast(ubyte)(n >> (i * 8)));
        }
        else
            destination.put(cast(ubyte)n);
    }

private:

}


private:

shared static this()
{
    ASN1OId.initializeDefaults();
}

unittest // ASN1OId.initializeDefaults, ASN1OId.idOf, ASN1OId.nameOf
{
    import pham.utl.test;
    traceUnitTest!("pham.cp")("unittest pham.cp.codec_asn1.ASN1OId.initializeDefaults, ASN1OId.idOf, ASN1OId.nameOf");

    auto v = ASN1OId.idOf("2.5.8.1.1");
    assert(v !is null);
    assert(v.name == "RSA");

    v = ASN1OId.idOf("1.3.132.0.10");
    assert(v !is null);
    assert(v.name == "secp256k1");

    v = ASN1OId.idOf("0.4.0.127.0.7.3.1.2.1");
    assert(v !is null);
    assert(v.name == "CertificateHolderAuthorizationTemplate");

    v = ASN1OId.nameOf("RSA");
    assert(v !is null);
    assert(v.id == "2.5.8.1.1");

    v = ASN1OId.nameOf("secp256k1");
    assert(v !is null);
    assert(v.id == "1.3.132.0.10");

    v = ASN1OId.nameOf("CertificateHolderAuthorizationTemplate");
    assert(v !is null);
    assert(v.id == "0.4.0.127.0.7.3.1.2.1");

    v = ASN1OId.idOf("This is invalid id?");
    assert(v is null);
    v = ASN1OId.idOf(null);
    assert(v is null);

    v = ASN1OId.nameOf("This is invalid name?");
    assert(v is null);
    v = ASN1OId.nameOf(null);
    assert(v is null);
}
