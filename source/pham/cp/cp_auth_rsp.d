/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2019 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
 * https://www.ietf.org/rfc/rfc5054.txt
   Conversion between integers and byte-strings assumes the most
   significant bytes are stored first, as per [TLS] and [SRP-RFC].  In
   the following text, if a conversion from integer to byte-string is
   implicit, the most significant byte in the resultant byte-string MUST
   be non-zero.  If a conversion is explicitly specified with the
   operator PAD(), the integer will first be implicitly converted, then
   the resultant byte-string will be left-padded with zeros (if
   necessary) until its length equals the implicitly-converted length of N.

   This document uses the variable names defined in [SRP-6]:
      N, g: group parameters (prime and generator)
      s: salt
      B, b: server's public and private values
      A, a: client's public and private values
      I: user name (aka "identity")
      P: password
      v: verifier
      k: SRP-6 multiplier

    The host stores passwords using the following formula:
      x = H(s, p)               (s is chosen randomly)
      v = g^x                   (computes password verifier)

    The host then keeps {I, s, v} in its password database. The authentication protocol
    itself goes as follows:
    User -> Host:  I, A = g^a                  (identifies self, a = random number)
    Host -> User:  s, B = kv + g^b             (sends salt, b = random number)

            Both:  u = H(A, B)

            User:  x = H(s, p)                 (user enters password)
            User:  S = (B - kg^x) ^ (a + ux)   (computes session key)
            User:  K = H(S)

            Host:  S = (Av^u) ^ b              (computes session key)
            Host:  K = H(S)

    Now the two parties have a shared, strong session key K. To complete authentication,
    they need to prove to each other that their keys match. One possible way:
    1. User -> Host:  M = H(H(N) xor H(g), H(I), s, A, B, K)
    2. Host -> User:  H(A, M, K)

    The two parties also employ the following safeguards:
    1. The user will abort if he receives B == 0 (mod N) or u == 0.
    2. The host will abort if it detects that A == 0 (mod N).
    3. The user must show his proof of K first. If the server detects that the user's proof is incorrect,
       it must abort without showing its own proof of K.
 *
 */

module pham.cp.cp_auth_rsp;

import std.conv : to;
import std.string : representation;
import std.typecons : Flag, No, Yes;

debug(debug_pham_cp_cp_auth_rsp) import std.stdio : writeln;

import pham.utl.utl_array : arrayOfChar;
import pham.utl.utl_array_static : ShortStringBuffer;
import pham.utl.utl_big_integer;
import pham.utl.utl_disposable : DisposableObject, DisposingReason;
import pham.utl.utl_numeric_parser : isHexDigit;
import pham.utl.utl_result : ResultCode;
public import pham.cp.cp_cipher : CipherBuffer, CipherKey, CipherRawKey;
public import pham.cp.cp_cipher_digest;
public import pham.cp.cp_random : CipherRandomGenerator;

nothrow @safe:

// minGroupSize (in bits) sets a lower bound on the size of DH groups
// that will pass certain internal checks. Defaults to 2048
enum minGroupSize = 2_048;

// minExponentSize (in bytes) for generating ephemeral private keys.
enum minExponentSize = 32;

struct PrimeGroup
{
nothrow @safe:

public:
    this(this) nothrow pure
    {
        _g = _g.dup;
        _N = _N.dup;
    }

    this(uint g, scope const(char)[] N, uint exponentSize,
         uint paddingSize = 0) pure
    {
        uint getPaddingSize()
        {
            auto N2 = NumericLexerOptions!char.isHexDigitPrefix(N) ? N[2..$] : N;

            uint result = 0;
            foreach (c; N2)
            {
                if (isHexDigit(c))
                    ++result;
            }
            return result;
        }

        this._g = BigInteger(g);
        this._N = CipherKey.hexDigitsToBigInteger(N);
        this._exponentSize = exponentSize;
        this._paddingSize = paddingSize != 0 ? paddingSize : getPaddingSize();
    }

    this(const(BigInteger) g, const(BigInteger) N, uint exponentSize, uint paddingSize) pure
    {
        this._g = g.dup;
        this._N = N.dup;
        this._exponentSize = exponentSize;
        this._paddingSize = paddingSize;
    }

    ~this() nothrow @safe pure
    {
        dispose(DisposingReason.destructor);
    }

    // For security reason, need to clear the secrete information
    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        _g.dispose(disposingReason);
        _N.dispose(disposingReason);
        _exponentSize = _paddingSize = 0;
        return ResultCode.ok;
    }

    uint maxExponentSize() const @nogc nothrow pure
    {
        return exponentSize > minExponentSize ? exponentSize : minExponentSize;
    }

    @property uint exponentSize() const @nogc pure
    {
        return _exponentSize;
    }

    @property const(BigInteger) g() const pure
    {
        return _g;
    }

    @property uint paddingSize() const @nogc pure
    {
        return _paddingSize;
    }

    @property const(BigInteger) N() const pure
    {
        return _N;
    }

private:
    BigInteger _g;
    BigInteger _N;
    uint _exponentSize;
    uint _paddingSize;
}

version(none) static immutable PrimeGroup prime1024; // Insecured one
version(none) static immutable PrimeGroup prime1536; // Insecured one
static immutable PrimeGroup prime2048;
static immutable PrimeGroup prime3072;
static immutable PrimeGroup prime4096;
static immutable PrimeGroup prime6144;
static immutable PrimeGroup prime8192;

struct AuthParameters
{
nothrow @safe:

public:
    this(DigestId digestId, DigestId proofDigestId,
        char separator = ':')
    {
        this(digestId, proofDigestId, prime2048, separator);
    }

    this(DigestId digestId, DigestId proofDigestId, const(PrimeGroup) group,
        char separator = ':')
    {
        this._hasher = Digester(digestId);
        this._proofHasher = Digester(proofDigestId);
        this._group = group;
        this._separator = separator;
    }
    
    // For security reason, need to clear the secrete information
    int dispose(const(DisposingReason) disposingReason = DisposingReason.dispose) nothrow pure @safe
    in
    {
        assert(disposingReason != DisposingReason.none);
    }
    do
    {
        //const(PrimeGroup) _group;
        _hasher.dispose(disposingReason);
        _proofHasher.dispose(disposingReason);
        _separator = '\0';
        return ResultCode.ok;
    }

    static CipherRawKey!ubyte generateSecret(const(uint) byteSize)
    {        
        CipherBuffer!ubyte result;
        CipherRandomGenerator rnd;
        return rnd.nextBytes(result, byteSize).toRawKey(); 
    }

    CipherRawKey!ubyte hash(const(BigInteger) n, Flag!"pad" pad)
    {
        DigestResult rTemp = void;
        auto bytes = pad 
            ? Auth.bytesFromBigIntegerPad(n, paddingSize)
            : Auth.bytesFromBigInteger(n);
        return CipherRawKey!ubyte(_hasher.begin()
            .digest(bytes)
            .finish(rTemp));
    }

    CipherRawKey!ubyte proofHash(const(BigInteger) n, Flag!"pad" pad)
    {
        DigestResult rTemp = void;
        auto bytes = pad 
            ? Auth.bytesFromBigIntegerPad(n, paddingSize)
            : Auth.bytesFromBigInteger(n);
        return CipherRawKey!ubyte(_hasher.begin()
            .digest(bytes)
            .finish(rTemp));
    }

    @property uint exponentSize() const @nogc pure
    {
        return _group.exponentSize;
    }

    @property ref const(PrimeGroup) group() const pure return
    {
        return _group;
    }

    @property ref Digester proofHasher() pure return
    {
        return _proofHasher;
    }

    @property ref Digester hasher() pure return
    {
        return _hasher;
    }

    @property uint hasherBits() const @nogc pure
    {
        return _hasher.digestBits;
    }

    @property uint hasherLength() const @nogc pure
    {
        return _hasher.digestLength;
    }

    @property uint maxExponentSize() const @nogc pure
    {
        return _group.maxExponentSize;
    }

    @property uint paddingSize() const @nogc pure
    {
        return _group.paddingSize;
    }

    @property char separator() const @nogc pure
    {
        return _separator;
    }

private:
    const(PrimeGroup) _group;
    Digester _hasher;
    Digester _proofHasher;
    char _separator = '\0';
}

class Auth : DisposableObject
{
nothrow @safe:

public:
    this(AuthParameters parameters, BigInteger k)
    {
        assert(parameters.group.g != 0);
        assert(parameters.group.N != 0);

        this._parameters = parameters;
        this._k = k == BigInteger.zero ? calculateK() : k;
    }

    static CipherRawKey!ubyte bytesFromBigInteger(scope const(BigInteger) n) pure
    {
        auto result = CipherKey.bytesFromBigInteger(n).reverse().removeFront(0);
        return result.empty ? CipherRawKey!ubyte([0]) : result;
    }

    static CipherRawKey!ubyte bytesFromBigIntegerPad(scope const(BigInteger) n, const(size_t) paddingSize) pure
    {
        auto result = bytesFromBigInteger(n);

        //if (paddingSize > result.length)
        //    return arrayOfChar(0, paddingSize - result.length) ~ result;

        return result.length > paddingSize
            ? result.chopFront(result.length - paddingSize)
            : result;
    }

    static BigInteger bytesToBigInteger(scope const(ubyte)[] bytes) pure
    {
        auto temp = CipherBuffer!ubyte(bytes);
        temp.reverse();
        temp.put(0);
        return CipherKey.bytesToBigInteger(temp[]);
    }

    // u = H(PAD(A), PAD(B))
    final BigInteger calculateU(const(BigInteger) A, const(BigInteger) B)
    {
        // error?
	    //if (!isPublicValid(A) || !isPublicValid(B))
        //    return BigInteger.zero;

        auto hasher = _parameters.hasher;

        DigestResult kTemp = void;
        auto rHash = hasher.begin()
            .digest(bytesFromBigIntegerPad(A, paddingSize))
            .digest(bytesFromBigIntegerPad(B, paddingSize))
            .finish(kTemp);
        auto result = bytesToBigInteger(rHash);

        debug(debug_pham_cp_cp_auth_rsp) debug writeln(__FUNCTION__, "(A=", A.toString(), ", A.pad=",
            bytesFromBigIntegerPad(A, paddingSize), ", B=", B.toString(), ", B.pad=", bytesFromBigIntegerPad(B, paddingSize),
            ", rHash=", rHash, ", result=", result, ")");

        return result;
	}

    // x = H(s, H(I | ':' | p))  (s=salt is chosen randomly)
    BigInteger calculateX(scope const(char)[] userName, scope const(char)[] userPassword, scope const(ubyte)[] salt)
    {
        auto hasher = _parameters.hasher;

        ubyte[1] digestSeparator = [cast(ubyte)parameters.separator];

        DigestResult iTemp = void;
        auto iHash = hasher.begin()
            .digest(userName.representation)
            .digest(digestSeparator)
            .digest(userPassword.representation)
            .finish(iTemp);

        DigestResult rTemp = void;
        auto rHash = hasher.begin()
            .digest(salt)
            .digest(iHash)
            .finish(rTemp);
        return bytesToBigInteger(rHash);
    }

    final CipherRawKey!ubyte digest(scope const(ubyte)[] v)
    {
        auto hasher = _parameters.hasher;

        DigestResult hashTemp = void;
        return CipherRawKey!ubyte(hasher.begin()
            .digest(v)
            .finish(hashTemp));
    }

    final CipherRawKey!ubyte digest(scope const(char)[] v)
    {
        return digest(v.representation);
    }

    final CipherRawKey!ubyte digest(const(BigInteger) v)
    {
        auto hasher = _parameters.hasher;

        DigestResult hashTemp = void;
        return CipherRawKey!ubyte(hasher.begin()
            .digest(bytesFromBigInteger(v))
            .finish(hashTemp));
    }

    final CipherRawKey!ubyte digestPad(const(BigInteger) v)
    {
        auto hasher = _parameters.hasher;

        DigestResult hashTemp = void;
        return CipherRawKey!ubyte(hasher.begin()
            .digest(bytesFromBigIntegerPad(v, paddingSize))
            .finish(hashTemp));
    }

    // IsPublicValid checks to see whether public A or B is valid within the group
    // A client can do very bad things by sending a malicious A to the server.
    // The server can do mildly bad things by sending a malicious B to the client.
    // This method is public in case the user wishes to check those values earlier than
    // than using SetOthersPublic(), which also performs this check.
	// There are three ways to fail.
	// 1. If we aren't checking with respect to a valid group
	// 2. If public paramater zero or a multiple of M
	// 3. If public parameter is not relatively prime to N (a bad group?)
    final bool isPublicValid(const(BigInteger) AorB)
    {
        auto r = remainder(AorB, N);
        if (r != 0 && r.sign == 0)
            return false;

        if (compare(greatestCommonDivisor(AorB, N), BigInteger.one) != 0)
            return false;

    	return true;
    }

    final CipherRawKey!ubyte proofDigest(const(BigInteger) v)
    {
        auto hasher = _parameters.proofHasher;

        DigestResult hashTemp = void;
        return CipherRawKey!ubyte(hasher.begin()
            .digest(bytesFromBigInteger(v).value)
            .finish(hashTemp));
    }

    string traceString() const
    {
        return "Auth.N=" ~ _parameters.group.N.toString()
		    ~ ", g=" ~ _parameters.group.g.toString()
		    ~ ", k=" ~ _k.toString()
		    ~ ", ephemeralPrivate=" ~ _ephemeralPrivate.toString()
		    ~ ", ephemeralPublic=" ~ _ephemeralPublic.toString();
    }

    @property final BigInteger ephemeralPrivate() pure
    {
        return _ephemeralPrivate;
    }

    // Hex digits
    @property final const(CipherRawKey!char) ephemeralPrivateKey() const pure
    {
        return CipherKey.hexDigitsFromBigInteger(_ephemeralPrivate);
    }

    @property final BigInteger ephemeralPublic() pure
    {
        return _ephemeralPublic;
    }

    // Hex digits
    @property final const(CipherRawKey!char) ephemeralPublicKey() const pure
    {
        return CipherKey.hexDigitsFromBigInteger(_ephemeralPublic);
    }

    @property final BigInteger g()
    {
        return (() @trusted => cast()_parameters.group.g)();
    }

    @property final BigInteger k()
    {
        return _k;
    }

    @property final BigInteger N()
    {
        return (() @trusted => cast()_parameters.group.N)();
    }

    @property uint paddingSize() const @nogc pure
    {
        return _parameters.paddingSize;
    }

    @property final ref AuthParameters parameters() pure
    {
        return _parameters;
    }

protected:
    // k = H(N, PAD(g))
    final BigInteger calculateK()
    {
        auto hasher = parameters.hasher;

        DigestResult kTemp = void;
        auto rHash = hasher.begin()
            .digest(bytesFromBigIntegerPad(N, paddingSize))
            .digest(bytesFromBigIntegerPad(g, paddingSize))
            .finish(kTemp);
        auto result = bytesToBigInteger(rHash);

        debug(debug_pham_cp_cp_auth_rsp) debug writeln(__FUNCTION__, "(N=", N.toString(),
            ", g=", g.toString(), ", result=", result.toString(), ")");

        return result;
    }

    final override int doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _ephemeralPrivate.dispose(disposingReason);
        _ephemeralPublic.dispose(disposingReason);
        _k.dispose(disposingReason);
        return ResultCode.ok;
    }

protected:
	BigInteger _ephemeralPrivate; // Private a or b (ephemeral secrets)
	BigInteger _ephemeralPublic; // Public A or B

private:
	BigInteger _k; // multiplier parameter
    AuthParameters _parameters;
}

class AuthClient : Auth
{
nothrow @safe:

public:
    this(AuthParameters parameters, BigInteger k)
    {
        super(parameters, k);
        
        auto secretKey = parameters.generateSecret(parameters.exponentSize);
        this._ephemeralPrivate = CipherKey.bytesToBigInteger(secretKey[]);
        this._ephemeralPublic = calculateA(_ephemeralPrivate);
    }

    version(unittest)
    this(AuthParameters parameters, BigInteger k, BigInteger ephemeralPrivate)
    {
        assert(ephemeralPrivate != 0);

        super(parameters, k);
        this._ephemeralPrivate = ephemeralPrivate;
        this._ephemeralPublic = calculateA(ephemeralPrivate);
    }

    /*
        I, P = <read from user>
        N, g, s, B = <read from server>
        a = random()
        A = g^a % N
        u = SHA1(PAD(A) | PAD(B))
        k = SHA1(N | PAD(g))
        x = SHA1(s | SHA1(I | ":" | P))
        <premaster secret> = (B - (k * g^x)) ^ (a + (u * x)) % N
    */
    final BigInteger calculatePremasterKey(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] salt, BigInteger serverPublicKey)
    {
        // Firebird algorithm
        version(all)
        {
            auto u = calculateU(ephemeralPublic, serverPublicKey);
            auto x = calculateX(userName, userPassword, salt);
            auto gx = modPow(g, x, N);
            BigInteger kgx;
            divRem(k * gx, N, kgx);
            auto bkgx = serverPublicKey - kgx;
            if (bkgx < 0)
                bkgx = bkgx + N;
            BigInteger diff;
            divRem(bkgx, N, diff);
            BigInteger ux;
            divRem(u * x, N, ux);
            BigInteger aux;
            divRem(ephemeralPrivate + ux, N, aux);
            auto result = modPow(diff, aux, N);

            debug(debug_pham_cp_cp_auth_rsp) debug writeln(__FUNCTION__, "(ephemeralPublic=", ephemeralPublic.toString(),
                ", ephemeralPrivate=", ephemeralPrivate.toString(), ", serverPublicKey=", serverPublicKey.toString(), ", u=", u.toString(),
                ", x=", x.toString(), ", gx=", gx.toString(), ", kgx=", kgx.toString(), ", bkgx=", bkgx.toString(), ", diff=", diff.toString(),
                ", ux=", ux.toString(), ", aux=", aux.toString(), ", result=", result.toString(), ")");
        }
        else
        {
            auto u = calculateU(ephemeralPublic, serverPublicKey);
            auto x = calculateX(userName, userPassword, salt);
            auto gx = modPow(g, x, N);
            auto kgx = (k * gx) % N;
            auto base = (serverPublicKey - kgx) % N;
            auto ux = (u * x) % N;
            auto exponent = (ephemeralPrivate + ux) % N;
            auto result = modPow(base, exponent, N);

            debug(debug_pham_cp_cp_auth_rsp) debug writeln(__FUNCTION__, "(ephemeralPublic=", ephemeralPublic.toString(),
                ", ephemeralPrivate=", ephemeralPrivate.toString(), ", serverPublicKey=", serverPublicKey.toString(), ", u=", u.toString(),
                ", x=", x.toString(), ", gx=", gx.toString(), ", kgx=", kgx.toString(), ", base=", base.toString(), ", ux=", ux.toString(),
                ", exponent=", exponent.toString(), ", result=", result.toString(), ")");
        }

        return result;
    }

    version(none)
    final bool isServerProofed(scope const(char)[] user, scope const(ubyte)[] salt,
        scope const(ubyte)[] serverProof) nothrow
    {
        if (!calculateM(user, salt))
            return false;
        else
            return m == serverProof;
    }

    version(none)
    final bool verify(scope const(char)[] user, scope const(ubyte)[] salt, scope const(char)[] serverProofHexs) nothrow
    {
        if (ephemeralPublicOther == 0)
            return false;

        auto key = makeKey();
        if (key.length == 0)
            return false;

        auto digester = parameters.hasher.digester;

		// H(A, M, K)
		// A — Public ephemeral values
		// M — Proof of K
		// K — Shared, strong session key
        ubyte[maxHashSize] hTemp = void;
        auto expected = BigInteger(digester.digest(hTemp,
            ephemeralPublic.toUBytes(), calculateProof(user, salt), key));
		auto server = hexCharToBigInteger(serverProofHexs);
        return server == expected;
    }

protected:
    // A = g^a % N
    final BigInteger calculateA(BigInteger ephemeralPrivate)
    {
        return modPow(g, ephemeralPrivate, N);
    }
}

version(none)
class AuthServer : Auth
{
public:
    this(AuthParameters parameters, BigInteger k)
    {
        super(parameters, k);
    }

    version(none)
    /*
    v: Your long term secret, v.

    k: If you wish to manually set the multiplier, little k, pass in
    a non-zero bigInt. If you set this to zero, then we will generate one for you.
    You need the same k on both server and client.
    */
    this(AuthParameters parameters, BigInteger v, BigInteger k) nothrow
    {
        assert(v != 0);

        super(parameters);
        this.v = v;
        this.k = k == 0 ? calculateK() : k;
        makeB();
    }

    version(none)
    /*
        N, g, s, v = <read from password file>
        b = random()
        k = SHA1(N | PAD(g))
        B = k*v + g^b % N
        A = <read from client>
        u = SHA1(PAD(A) | PAD(B))
        <premaster secret> = (A * v^u) ^ b % N
    */
    final override CipherRawKey!ubyte makeKey() nothrow
    {
        if (ephemeralPublicOther == 0)
        {
            _premasterKey = 0;
            _key = null;
            return _key;
        }

        auto u = makeU();
	    if (u == 0)
        {
            _premasterKey = 0;
            _key = null;
            return _key;
        }

        if (_key.length != 0)
            return _key;

        auto digester = parameters.hasher.digester;
        auto group = parameters.group;

        // base
        auto b = modPow(v, u, group.n);
        b *= ephemeralPublicOther;

        // exponent
        auto e = ephemeralPrivate;

        ubyte[maxHashSize] kTemp = void;
        _premasterKey = modPow(b, e, group.n);
        _key = digester.digest(kTemp, _premasterKey.toUBytes()).dup;

        return _key;
    }

protected:
    version(none)
    final void makeB() nothrow
    {
        // B = k*v + g^b % N
        auto group = parameters.group;

        auto term1 = (k * v) % group.n;

        auto term2 = modPow(group.g, ephemeralPrivate, group.n);

        _ephemeralPublic = (term1 + term2) % group.n;
    }
}


// Any below codes are private
private:


// D does not allow to inline initialize immutable at compile time
// so do it at module constructor
// Leading 00 to indicate a positive number
shared static this() nothrow @safe
{
    version(none)
    prime1024 = immutable PrimeGroup(
        2,
        "EEAF0AB9 ADB38DD6 9C33F80A FA8FC5E8 60726187 75FF3C0B 9EA2314C 9C256576
         D674DF74 96EA81D3 383B4813 D692C6E0 E0D5D8E2 50B98BE4 8E495C1D 6089DAD1
         5DC7D7B4 6154D6B6 CE8EF4AD 69B15D49 82559B29 7BCF1885 C529F566 660E57EC
         68EDBC3C 05726CC0 2FD4CBF4 976EAA9A FD5138FE 8376435B 9FC61D2F C0EB06E3",
        32); //?

    version(none)
    prime1536 = immutable PrimeGroup(
        2,
        "9DEF3CAF B939277A B1F12A86 17A47BBB DBA51DF4 99AC4C80 BEEEA961 4B19CC4D
         5F4F5F55 6E27CBDE 51C6A94B E4607A29 1558903B A0D0F843 80B655BB 9A22E8DC
         DF028A7C EC67F0D0 8134B1C8 B9798914 9B609E0B E3BAB63D 47548381 DBC5B1FC
         764E3F4B 53DD9DA1 158BFD3E 2B9C8CF5 6EDF0195 39349627 DB2FD53D 24B7C486
         65772E43 7D6C7F8C E442734A F7CCB7AE 837C264A E3A9BEB8 7F8A2FE9 B8B5292E
         5A021FFF 5E91479E 8CE7A28C 2442C6F3 15180F93 499A234D CF76E3FE D135F9BB",
        32); //?

    prime2048 = immutable PrimeGroup(
        2,
        "AC6BDB41 324A9A9B F166DE5E 1389582F AF72B665 1987EE07 FC319294 3DB56050
         A37329CB B4A099ED 8193E075 7767A13D D52312AB 4B03310D CD7F48A9 DA04FD50
         E8083969 EDB767B0 CF609517 9A163AB3 661A05FB D5FAAAE8 2918A996 2F0B93B8
         55F97993 EC975EEA A80D740A DBF4FF74 7359D041 D5C33EA7 1D281E44 6B14773B
         CA97B43A 23FB8016 76BD207A 436C6481 F1D2B907 8717461A 5B9D32E6 88F87748
         544523B5 24B0D57D 5EA77A27 75D2ECFA 032CFBDB F52FB378 61602790 04E57AE6
         AF874E73 03CE5329 9CCC041C 7BC308D8 2A5698F3 A8D0C382 71AE35F8 E9DBFBB6
	     94B5C803 D89F7AE4 35DE236D 525F5475 9B65E372 FCD68EF2 0FA7111F 9E4AFF73",
        32);

    prime3072 = immutable PrimeGroup(
        5,
        "FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1 29024E08 8A67CC74
         020BBEA6 3B139B22 514A0879 8E3404DD EF9519B3 CD3A431B 302B0A6D F25F1437
         4FE1356D 6D51C245 E485B576 625E7EC6 F44C42E9 A637ED6B 0BFF5CB6 F406B7ED
         EE386BFB 5A899FA5 AE9F2411 7C4B1FE6 49286651 ECE45B3D C2007CB8 A163BF05
         98DA4836 1C55D39A 69163FA8 FD24CF5F 83655D23 DCA3AD96 1C62F356 208552BB
         9ED52907 7096966D 670C354E 4ABC9804 F1746C08 CA18217C 32905E46 2E36CE3B
         E39E772C 180E8603 9B2783A2 EC07A28F B5C55DF0 6F4C52C9 DE2BCBF6 95581718
	     3995497C EA956AE5 15D22618 98FA0510 15728E5A 8AAAC42D AD33170D 04507A33
         A85521AB DF1CBA64 ECFB8504 58DBEF0A 8AEA7157 5D060C7D B3970F85 A6E1E4C7
         ABF5AE8C DB0933D7 1E8C94E0 4A25619D CEE3D226 1AD2EE6B F12FFA06 D98A0864
         D8760273 3EC86A64 521F2B18 177B200C BBE11757 7A615D6C 770988C0 BAD946E2
         08E24FA0 74E5AB31 43DB5BFC E0FD108E 4B82D120 A93AD2CA FFFFFFFF FFFFFFFF",
        32);

    prime4096 = immutable PrimeGroup(
        5,
        "FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1 29024E08 8A67CC74
         020BBEA6 3B139B22 514A0879 8E3404DD EF9519B3 CD3A431B 302B0A6D F25F1437
         4FE1356D 6D51C245 E485B576 625E7EC6 F44C42E9 A637ED6B 0BFF5CB6 F406B7ED
         EE386BFB 5A899FA5 AE9F2411 7C4B1FE6 49286651 ECE45B3D C2007CB8 A163BF05
         98DA4836 1C55D39A 69163FA8 FD24CF5F 83655D23 DCA3AD96 1C62F356 208552BB
         9ED52907 7096966D 670C354E 4ABC9804 F1746C08 CA18217C 32905E46 2E36CE3B
         E39E772C 180E8603 9B2783A2 EC07A28F B5C55DF0 6F4C52C9 DE2BCBF6 95581718
	     3995497C EA956AE5 15D22618 98FA0510 15728E5A 8AAAC42D AD33170D 04507A33
         A85521AB DF1CBA64 ECFB8504 58DBEF0A 8AEA7157 5D060C7D B3970F85 A6E1E4C7
         ABF5AE8C DB0933D7 1E8C94E0 4A25619D CEE3D226 1AD2EE6B F12FFA06 D98A0864
         D8760273 3EC86A64 521F2B18 177B200C BBE11757 7A615D6C 770988C0 BAD946E2
         08E24FA0 74E5AB31 43DB5BFC E0FD108E 4B82D120 A9210801 1A723C12 A787E6D7
         88719A10 BDBA5B26 99C32718 6AF4E23C 1A946834 B6150BDA 2583E9CA 2AD44CE8
         DBBBC2DB 04DE8EF9 2E8EFC14 1FBECAA6 287C5947 4E6BC05D 99B2964F A090C3A2
	     233BA186 515BE7ED 1F612970 CEE2D7AF B81BDD76 2170481C D0069127 D5B05AA9
         93B4EA98 8D8FDDC1 86FFB7DC 90A6C08F 4DF435C9 34063199 FFFFFFFF FFFFFFFF",
        38);

    prime6144 = immutable PrimeGroup(
        5,
        "FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1 29024E08 8A67CC74
         020BBEA6 3B139B22 514A0879 8E3404DD EF9519B3 CD3A431B 302B0A6D F25F1437
         4FE1356D 6D51C245 E485B576 625E7EC6 F44C42E9 A637ED6B 0BFF5CB6 F406B7ED
         EE386BFB 5A899FA5 AE9F2411 7C4B1FE6 49286651 ECE45B3D C2007CB8 A163BF05
         98DA4836 1C55D39A 69163FA8 FD24CF5F 83655D23 DCA3AD96 1C62F356 208552BB
         9ED52907 7096966D 670C354E 4ABC9804 F1746C08 CA18217C 32905E46 2E36CE3B
         E39E772C 180E8603 9B2783A2 EC07A28F B5C55DF0 6F4C52C9 DE2BCBF6 95581718
	     3995497C EA956AE5 15D22618 98FA0510 15728E5A 8AAAC42D AD33170D 04507A33
         A85521AB DF1CBA64 ECFB8504 58DBEF0A 8AEA7157 5D060C7D B3970F85 A6E1E4C7
         ABF5AE8C DB0933D7 1E8C94E0 4A25619D CEE3D226 1AD2EE6B F12FFA06 D98A0864
         D8760273 3EC86A64 521F2B18 177B200C BBE11757 7A615D6C 770988C0 BAD946E2
         08E24FA0 74E5AB31 43DB5BFC E0FD108E 4B82D120 A9210801 1A723C12 A787E6D7
         88719A10 BDBA5B26 99C32718 6AF4E23C 1A946834 B6150BDA 2583E9CA 2AD44CE8
         DBBBC2DB 04DE8EF9 2E8EFC14 1FBECAA6 287C5947 4E6BC05D 99B2964F A090C3A2
	     233BA186 515BE7ED 1F612970 CEE2D7AF B81BDD76 2170481C D0069127 D5B05AA9
         93B4EA98 8D8FDDC1 86FFB7DC 90A6C08F 4DF435C9 34028492 36C3FAB4 D27C7026
         C1D4DCB2 602646DE C9751E76 3DBA37BD F8FF9406 AD9E530E E5DB382F 413001AE
         B06A53ED 9027D831 179727B0 865A8918 DA3EDBEB CF9B14ED 44CE6CBA CED4BB1B
         DB7F1447 E6CC254B 33205151 2BD7AF42 6FB8F401 378CD2BF 5983CA01 C64B92EC
         F032EA15 D1721D03 F482D7CE 6E74FEF6 D55E702F 46980C82 B5A84031 900B1C9E
         59E7C97F BEC7E8F3 23A97A7E 36CC88BE 0F1D45B7 FF585AC5 4BD407B2 2B4154AA
	     CC8F6D7E BF48E1D8 14CC5ED2 0F8037E0 A79715EE F29BE328 06A1D58B B7C5DA76
         F550AA3D 8A1FBFF0 EB19CCB1 A313D55C DA56C9EC 2EF29632 387FE8D7 6E3C0468
         043E8F66 3F4860EE 12BF2D5B 0B7474D6 E694F91E 6DCC4024 FFFFFFFF FFFFFFFF",
        43);

    prime8192 = immutable PrimeGroup(
        19,
        "FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1 29024E08 8A67CC74
         020BBEA6 3B139B22 514A0879 8E3404DD EF9519B3 CD3A431B 302B0A6D F25F1437
         4FE1356D 6D51C245 E485B576 625E7EC6 F44C42E9 A637ED6B 0BFF5CB6 F406B7ED
         EE386BFB 5A899FA5 AE9F2411 7C4B1FE6 49286651 ECE45B3D C2007CB8 A163BF05
         98DA4836 1C55D39A 69163FA8 FD24CF5F 83655D23 DCA3AD96 1C62F356 208552BB
         9ED52907 7096966D 670C354E 4ABC9804 F1746C08 CA18217C 32905E46 2E36CE3B
         E39E772C 180E8603 9B2783A2 EC07A28F B5C55DF0 6F4C52C9 DE2BCBF6 95581718
	     3995497C EA956AE5 15D22618 98FA0510 15728E5A 8AAAC42D AD33170D 04507A33
         A85521AB DF1CBA64 ECFB8504 58DBEF0A 8AEA7157 5D060C7D B3970F85 A6E1E4C7
         ABF5AE8C DB0933D7 1E8C94E0 4A25619D CEE3D226 1AD2EE6B F12FFA06 D98A0864
         D8760273 3EC86A64 521F2B18 177B200C BBE11757 7A615D6C 770988C0 BAD946E2
         08E24FA0 74E5AB31 43DB5BFC E0FD108E 4B82D120 A9210801 1A723C12 A787E6D7
         88719A10 BDBA5B26 99C32718 6AF4E23C 1A946834 B6150BDA 2583E9CA 2AD44CE8
         DBBBC2DB 04DE8EF9 2E8EFC14 1FBECAA6 287C5947 4E6BC05D 99B2964F A090C3A2
	     233BA186 515BE7ED 1F612970 CEE2D7AF B81BDD76 2170481C D0069127 D5B05AA9
         93B4EA98 8D8FDDC1 86FFB7DC 90A6C08F 4DF435C9 34028492 36C3FAB4 D27C7026
         C1D4DCB2 602646DE C9751E76 3DBA37BD F8FF9406 AD9E530E E5DB382F 413001AE
         B06A53ED 9027D831 179727B0 865A8918 DA3EDBEB CF9B14ED 44CE6CBA CED4BB1B
         DB7F1447 E6CC254B 33205151 2BD7AF42 6FB8F401 378CD2BF 5983CA01 C64B92EC
         F032EA15 D1721D03 F482D7CE 6E74FEF6 D55E702F 46980C82 B5A84031 900B1C9E
         59E7C97F BEC7E8F3 23A97A7E 36CC88BE 0F1D45B7 FF585AC5 4BD407B2 2B4154AA
	     CC8F6D7E BF48E1D8 14CC5ED2 0F8037E0 A79715EE F29BE328 06A1D58B B7C5DA76
         F550AA3D 8A1FBFF0 EB19CCB1 A313D55C DA56C9EC 2EF29632 387FE8D7 6E3C0468
         043E8F66 3F4860EE 12BF2D5B 0B7474D6 E694F91E 6DBE1159 74A3926F 12FEE5E4
         38777CB6 A932DF8C D8BEC4D0 73B931BA 3BC832B6 8D9DD300 741FA7BF 8AFC47ED
         2576F693 6BA42466 3AAB639C 5AE4F568 3423B474 2BF1C978 238F16CB E39D652D
         E3FDB8BE FC848AD9 22222E04 A4037C07 13EB57A8 1A23F0C7 3473FC64 6CEA306B
         4BCBC886 2F8385DD FA9D4B7F A2C087E8 79683303 ED5BDD3A 062B3CF5 B3A278A6
	     6D2A13F8 3F44F82D DF310EE0 74AB6A36 4597E899 A0255DC1 64F31CC5 0846851D
         F9AB4819 5DED7EA1 B1D510BD 7EE74D73 FAF36BC3 1ECFA268 359046F4 EB879F92
         4009438B 481C6CD7 889A002E D5EE382B C9190DA6 FC026E47 9558E447 5677E9AA
         9E3050E2 765694DF C81F56E8 80B96E71 60C980DD 98EDD3DF FFFFFFFF FFFFFFFF",
        48);
}

@safe unittest // Auth.bytesToBigInteger
{
    import pham.utl.utl_convert : bytesFromHexs;

    assert(Auth.bytesToBigInteger(bytesFromHexs("BADAD8293C6296A5E190B90189CC983140C933CC")).toString() == "1066752676112117711667100034894519583952173872076");
    assert(Auth.bytesToBigInteger(bytesFromHexs("C4EA21BB365BBEEAF5F2C654883E56D11E43C44E")).toString() == "1124183503868421757928291737012660252296180122702");
    assert(Auth.bytesToBigInteger(bytesFromHexs("325B32AC6CDC607502C4532300FADD4D3A0CDC1C")).toString() == "287483320641822846566806844311705592438316653596");
}

nothrow @safe unittest // Auth.bigIntegerToBytes
{
    import pham.utl.utl_convert : bytesToHexs;

    assert(bytesToHexs(Auth.bytesFromBigInteger(CipherKey.digitsToBigInteger("58543554083751952442334332707885450963256912723720014361224396835623580320574993412213112731622008780624513837590415042361332636920155374789034615041232473542789648377986158701807740526423554224690384086846078749662234094040670372520229647584994218966915554154095758043112636200250640433313973626261330006062"))) == "535E68E994A09E4C230894A6CC5F2B2485048097578E647222329B71A0AE81A91ADB0130AFEA1137DC1D2E6E22B0344C27C1572EDC5458B467087F05949B06B48F93E24D03A6320DCD07650E427F15F29DCDC90BAE5C81B37F418AB2CD48C27E2B919526A02AF70DC8FC0AED061B44CD3B17FB5042043FD2EDBE81296075102E");
    assert(bytesToHexs(Auth.bytesFromBigInteger(CipherKey.digitsToBigInteger("28749804614170657751613395335352001644021045590210914186913541716332978472699287641712130718432436775513509435910353882602931518835680441332783686729305742324521039220455708164504634943313672661596106590080117722530992561561401591892583596939561753640930289078202910469465603085941318098275740297449693738855"))) == "28F0EAAB25F8A11AA5134393599A38F32C04687898BD9F09A5235342AAD6371680F47782A581C3553A56308F3EA8C022EBA5EAC56C51F821574B2538F667748163D1AE71EB30B55E48678735A08783BC34D6434C44668DAE44056744CF95C182600D0BD25BF4CCF9FACFCF2C0EEFC07CBE0959D307BBB833A281544BC4CB7767");
    assert(bytesToHexs(Auth.bytesFromBigInteger(CipherKey.digitsToBigInteger("28749804614170657751613395335352001644021045590210914186913541716332978472699287641712130718432436775513509435910353882602931518835680441332783686729305742324521039220455708164504634943313672661596106590080117722530992561561401591892583596939561753640930289078202910469465603085941318098275740297449693738855"))) == "28F0EAAB25F8A11AA5134393599A38F32C04687898BD9F09A5235342AAD6371680F47782A581C3553A56308F3EA8C022EBA5EAC56C51F821574B2538F667748163D1AE71EB30B55E48678735A08783BC34D6434C44668DAE44056744CF95C182600D0BD25BF4CCF9FACFCF2C0EEFC07CBE0959D307BBB833A281544BC4CB7767");
    assert(bytesToHexs(Auth.bytesFromBigInteger(CipherKey.digitsToBigInteger("28749804614170657751613395335352001644021045590210914186913541716332978472699287641712130718432436775513509435910353882602931518835680441332783686729305742324521039220455708164504634943313672661596106590080117722530992561561401591892583596939561753640930289078202910469465603085941318098275740297449693738855"))) == "28F0EAAB25F8A11AA5134393599A38F32C04687898BD9F09A5235342AAD6371680F47782A581C3553A56308F3EA8C022EBA5EAC56C51F821574B2538F667748163D1AE71EB30B55E48678735A08783BC34D6434C44668DAE44056744CF95C182600D0BD25BF4CCF9FACFCF2C0EEFC07CBE0959D307BBB833A281544BC4CB7767");
}
