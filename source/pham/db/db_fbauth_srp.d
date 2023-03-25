/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2019 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.db.fbauth_srp;

import std.algorithm.mutation : reverse;
import std.conv : to;
import std.string : representation;
import std.typecons : Flag, No, Yes;

version (TraceFunction) import pham.utl.test;
import pham.utl.big_integer;
import pham.utl.disposable : DisposingReason, isDisposing;
import pham.utl.object : bytesFromHexs, bytesToHexs;
import pham.cp.auth_rsp;
import pham.db.auth;
import pham.db.message;
import pham.db.type : DbScheme;
import pham.db.fbauth;
import pham.db.fbisc : FbIscText;

nothrow @safe:

abstract class FbAuthSrp : FbAuth
{
nothrow @safe:

public:
    this(DigestId digestId, DigestId proofDigestId)
    in
    {
        assert(digestId == DigestId.sha1
               || digestId == DigestId.sha256
               || digestId == DigestId.sha384
               || digestId == DigestId.sha512);

        assert(proofDigestId == DigestId.sha1
               || proofDigestId == DigestId.sha256
               || proofDigestId == DigestId.sha384
               || proofDigestId == DigestId.sha512);
    }
    do
    {
        this._authClient = new AuthClient(AuthParameters(digestId, proofDigestId, fbPrime), CipherKey.digitsToBigInteger(K));
    }

    final ResultStatus calculateProof(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        version (TraceFunction) traceFunction("userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        auto status = parseServerAuthData(serverAuthData);
        if (status.isError)
            return status;

        auto normalizedUserName = normalizeUserName(userName);
        auto serverPublicKeyInt = serverPublicKeyAsBigInteger;
        scope (exit)
            serverPublicKeyInt.dispose();

        _premasterKey = _authClient.calculatePremasterKey(normalizedUserName, userPassword, serverSalt, serverPublicKeyInt);
        _proof = calculateProof(normalizedUserName, userPassword, serverSalt, serverPublicKeyInt);
        authData = CipherBuffer!ubyte(bytesToHexs(_proof).representation());
        return ResultStatus.ok();
    }

    final override ResultStatus getAuthData(const(int) state, scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] serverAuthData, ref CipherBuffer!ubyte authData)
    {
        version (TraceFunction) traceFunction("_nextState=", _nextState, ", state=", state, ", userName=", userName, ", serverAuthData=", serverAuthData.dgToHex());

        auto status = checkAdvanceState(state);
        if (status.isError)
            return status;

        if (state == 0)
        {
            authData = CipherBuffer!ubyte(publicKey());
            return ResultStatus.ok();
        }
        else if (state == 1)
            return calculateProof(userName, userPassword, serverAuthData, authData);
        else
            assert(0);
    }

    final override size_t maxSizeServerAuthData(out size_t maxSaltLength) const pure
    {
        maxSaltLength = saltLength * 2;
        // ((saltLength + 1) * 2) + ((keyLength + 1) * 2)
        return (saltLength + keyLength + 2) * 2;  //+2 for leading size data
    }
    
    final override CipherRawKey!ubyte sessionKey()
    {
        return _authClient.digest(_premasterKey);
    }

    @property final override bool canCryptedConnection() const pure
    {
        return true;
    }

    @property final override bool isSymantic() const @nogc pure
    {
        return true;
    }

    @property final override int multiStates() const @nogc pure
    {
        return 2; // No verification
    }

    @property final override const(CipherRawKey!ubyte) privateKey() const
    {
        return CipherRawKey!ubyte(_authClient.ephemeralPrivateKey().representation());
    }

    @property final override const(CipherRawKey!ubyte) publicKey() const
    {
        return CipherRawKey!ubyte(_authClient.ephemeralPublicKey().representation());
    }

    @property final BigInteger serverPublicKeyAsBigInteger() const pure
    {
        return CipherKey.hexDigitsToBigInteger(serverPublicKey);
    }

    @property final override string sessionKeyName() const pure
    {
        return "Symmetric";
    }

protected:
    version (unittest)
    this(DigestId digestId, DigestId proofDigestId, BigInteger ephemeralPrivate)
    {
        this._authClient = new AuthClient(AuthParameters(digestId, proofDigestId, fbPrime), CipherKey.digitsToBigInteger(K), ephemeralPrivate);

        version (TraceFunction) traceFunction(this._authClient.traceString());
    }

    final ubyte[] calculateProof(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] salt, const(BigInteger) serverPublicKey)
	{
        auto parameters = _authClient.parameters;
        auto proofHasher = parameters.proofHasher;

        auto K = _authClient.digest(_premasterKey);
		auto n1 = Auth.bytesToBigInteger(_authClient.digest(_authClient.N));
		auto n2 = Auth.bytesToBigInteger(_authClient.digest(_authClient.g));
		n1 = modPow(n1, n2, _authClient.N);
		n2 = Auth.bytesToBigInteger(_authClient.digest(userName));

        DigestResult hashTemp = void;
        auto M = proofHasher.begin()
            .digest(Auth.bytesFromBigInteger(n1))
            .digest(Auth.bytesFromBigInteger(n2))
            .digest(salt)
            .digest(Auth.bytesFromBigInteger(_authClient.ephemeralPublic))
            .digest(Auth.bytesFromBigInteger(serverPublicKey))
            .digest(K)
            .finish(hashTemp).dup;

        version (TraceFunction)
        {
		    traceFunction("userName=", userName,
                ", salt=", salt.dgToHex(),
                ", serverPublicKey=", serverPublicKey.toString(),
                ", _premasterKey=", _premasterKey.toString(),
                ", n1=", n1.toString(),
		        ", n2=", n2.toString(),
		        ", _authClient.ephemeralPrivate=", _authClient.ephemeralPrivate.toString(),
		        ", _authClient.ephemeralPublic=", _authClient.ephemeralPublic.toString(),
                ", K=", K,
                ", M=", M);
        }

        return M;
    }

    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        if (_authClient !is null)
        {
            _authClient.dispose(disposingReason);
            if (isDisposing(disposingReason))
                _authClient = null;
        }
        _premasterKey.dispose(disposingReason);
        _proof.dispose(disposingReason);
        super.doDispose(disposingReason);
    }

private:
    static immutable K = "1277432915985975349439481660349303019122249719989";
    static immutable N = "161854874649776085868045952190159031555772097014435707776279513538616175047026058065927714606879676219064271341818754038806823814541886861147177045257236811627035155212310813305487929926508522581710604504792711726648563877865328333166885998671854094528177699206377434633696300213499023964016345755132798642663";
    enum keyLength = 128;
    enum saltLength = 32;

    AuthClient _authClient;
    BigInteger _premasterKey;
    CipherRawKey!ubyte _proof;
}

class FbAuthSrpSHA1 : FbAuthSrp
{
nothrow @safe:

public:
    this()
    {
        super(DigestId.sha1, DigestId.sha1);
    }

    @property final override string name() const pure
    {
        return FbIscText.authSrp1Name;
    }

protected:
    version (unittest)
    this(BigInteger ephemeralPrivate)
    {
        super(DigestId.sha1, DigestId.sha1, ephemeralPrivate);
    }
}

class FbAuthSrpSHA256 : FbAuthSrp
{
nothrow @safe:

public:
    this()
    {
        super(DigestId.sha1, DigestId.sha256);
    }

    @property final override string name() const pure
    {
        return FbIscText.authSrp256Name;
    }

protected:
    version (unittest)
    this(BigInteger ephemeralPrivate)
    {
        super(DigestId.sha1, DigestId.sha256, ephemeralPrivate);
    }
}

class FbAuthSrpSHA384 : FbAuthSrp
{
nothrow @safe:

public:
    this()
    {
        super(DigestId.sha1, DigestId.sha384);
    }

    @property final override string name() const pure
    {
        return FbIscText.authSrp384Name;
    }

protected:
    version (unittest)
    this(BigInteger ephemeralPrivate)
    {
        super(DigestId.sha1, DigestId.sha384, ephemeralPrivate);
    }
}

class FbAuthSrpSHA512 : FbAuthSrp
{
nothrow @safe:

public:
    this()
    {
        super(DigestId.sha1, DigestId.sha512);
    }

    @property final override string name() const pure
    {
        return FbIscText.authSrp512Name;
    }

protected:
    version (unittest)
    this(BigInteger ephemeralPrivate)
    {
        super(DigestId.sha1, DigestId.sha512, ephemeralPrivate);
    }
}


// Any below codes are private
private:

shared static this()
{
    DbAuth.registerAuthMap(DbAuthMap(FbIscText.authSrp1Name, DbScheme.fb, &createAuthSrpSHA1));
    DbAuth.registerAuthMap(DbAuthMap(FbIscText.authSrp256Name, DbScheme.fb, &createAuthSrpSHA256));
    DbAuth.registerAuthMap(DbAuthMap(FbIscText.authSrp384Name, DbScheme.fb, &createAuthSrpSHA384));
    DbAuth.registerAuthMap(DbAuthMap(FbIscText.authSrp512Name, DbScheme.fb, &createAuthSrpSHA512));
}

DbAuth createAuthSrpSHA1()
{
    return new FbAuthSrpSHA1();
}

DbAuth createAuthSrpSHA256()
{
    return new FbAuthSrpSHA256();
}

DbAuth createAuthSrpSHA384()
{
    return new FbAuthSrpSHA384();
}

DbAuth createAuthSrpSHA512()
{
    return new FbAuthSrpSHA512();
}

static immutable PrimeGroup fbPrime;

shared static this()
{
    fbPrime = immutable PrimeGroup(
        2,
        "E67D2E99 4B2F900C 3F41F08F 5BB2627E D0D49EE1 FE767A52 EFCD565C D6E76881
         2C3E1E9C E8F0A8BE A6CB13CD 29DDEBF7 A96D4A93 B55D488D F099A15C 89DCB064
         0738EB2C BDD9A8F7 BAB561AB 1B0DC1C6 CDABF303 264A08D1 BCA932D1 F1EE428B
         619D970F 342ABA9A 65793B8B 2F041AE5 364350C1 6F735F56 ECBCA87B D57B29E7",
        FbAuthSrp.saltLength,
        FbAuthSrp.keyLength);
}

nothrow @safe unittest // PrimeGroup
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.fbauth_srp.PrimeGroup");

    assert(fbPrime.N.toString() == FbAuthSrp.N);
    assert(fbPrime.g.toString() == "2");
    assert(fbPrime.paddingSize == FbAuthSrp.keyLength);
}

version (unittest)
{
    import std.string : representation;
    import std.conv : to;
    import pham.utl.test;

    auto testUserName = "SYSDBA";
    auto testUserPassword = "masterkey";

    void testCheckSHA1(const(char)[] digitPrivateKey,
        const(char)[] digitExpectedPublicKey,
        const(char)[] serverHexAuthData,
        const(char)[] expectedHexProof,
        const(char)[] expectedHexServerSalt,
        const(char)[] expectedHexServerPublicKey,
        const(char)[] expectedDigitServerPublicKey,
        size_t line = __LINE__)
    {
        auto privateKey = CipherKey.digitsToBigInteger(digitPrivateKey);
        auto serverAuthData = bytesFromHexs(serverHexAuthData);
        auto client = new FbAuthSrpSHA1(privateKey);
        CipherBuffer!ubyte proof;
        assert(client.calculateProof(testUserName, testUserPassword, serverAuthData, proof).isOK);
        assert(client._authClient.ephemeralPublic.toString() == digitExpectedPublicKey,
            "digitExpectedPublicKey(" ~ to!string(line) ~ "): " ~ client._authClient.ephemeralPublic.toString() ~ " ? " ~ digitExpectedPublicKey);
        assert(bytesToHexs(client.serverPublicKey) == expectedHexServerPublicKey,
            "expectedHexServerPublicKey(" ~ to!string(line) ~ "): " ~ bytesToHexs(client.serverPublicKey) ~ " ? " ~ expectedHexServerPublicKey);
        assert(bytesToHexs(client.serverSalt) == expectedHexServerSalt,
            "expectedHexServerSalt(" ~ to!string(line) ~ "): " ~ bytesToHexs(client.serverSalt) ~ " ? " ~ expectedHexServerSalt);
        auto serverPublicKey = client.serverPublicKeyAsBigInteger;
        assert(serverPublicKey.toString() == expectedDigitServerPublicKey,
            "expectedDigitServerPublicKey(" ~ to!string(line) ~ "): " ~ serverPublicKey.toString() ~ " ? " ~ expectedDigitServerPublicKey);
        assert(proof == expectedHexProof.representation(),
            "expectedHexProof(" ~ to!string(line) ~ "): " ~ cast(const(char)[])(proof[]) ~ " ? " ~ expectedHexProof);

        client.dispose();
        client = null;
    }
}

nothrow @safe unittest // FbAuthSrpSHA1
{
    import pham.utl.test;
    traceUnitTest("unittest pham.db.fbauth_srp.FbAuthSrpSHA1");

    testCheckSHA1(
        /*digitPrivateKey*/ "264905762513559650080771073972109248903",
        /*digitExpectedPublicKey*/ "20683020699665853524089952214242729025570102331355286896164651135690756690875771106556553465927252488139803212504773984793490588986767319872337272030442815731428721361389194577481083428832457789266753718602245677204767791176476438551576288962556819987630078684529566279195237212923198916151796921004472200100",
        /*serverHexAuthData*/ "400043414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443000141454444374133423436343346313545333943364232453835333941334442464336433231444530444542303632354433463430374337453234384435303343333832413442353646334138323131413943393443433044343137333334303731333636443833323732413031433433463539363846424130423842363446313344334437454637353042354246463536314238414630323645314333434234424345453330413931324541384236374337463935424231363642423331334337374343424533314538334546413438454634464339393442354234383543454137394142333139344343303542303032383739383946423138423539323542",
        /*expectedHexProof*/ "13B25FD696423778F29DEAA266F4B88C40CC6B7A",
        /*expectedHexServerSalt*/ "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443",
        /*expectedHexServerPublicKey*/ "41454444374133423436343346313545333943364232453835333941334442464336433231444530444542303632354433463430374337453234384435303343333832413442353646334138323131413943393443433044343137333334303731333636443833323732413031433433463539363846424130423842363446313344334437454637353042354246463536314238414630323645314333434234424345453330413931324541384236374337463935424231363642423331334337374343424533314538334546413438454634464339393442354234383543454137394142333139344343303542303032383739383946423138423539323542",
        /*expectedDigitServerPublicKey*/ "122794481691256336976092504484682159342073724919120490560325361482978121758107403785116811617321015749520781999274663407045551768201722343482077317182691516688493237430938639003996055723030390419024244864218313640971850213487122457987110730006824960154761449277369233202613446097587560665634914036217458037339");

    testCheckSHA1(
        /*digitPrivateKey*/ "270171508735298645974390825330911403670",
        /*digitExpectedPublicKey*/ "90601182554443833646240732529595335357718206973596771208700719399606004823938813613233818285223851022085728368640419211513647539405419744687959875936482152456343610020609119700028320381695401814333844670102621019521662806635505332344045469300581224121204528440759728394449869884840811226751426023025109979600",
        /*serverHexAuthData*/ "400043414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443000135464646374337314146444330384434333143443430304438384330424633444545414131353345423135423646383846364342463932424339414538304445383937383946463733323542313236364535343741373645433444424233313542373343324236464545413146303833373944453641353545394542314434354541453544303931304630313630433141414646333330423544454333334646423837303535423641303138434444423534443341373134434345383842433442384338333343444135303938344630463131383234343635444534454636423034423641384638373134304642433738423544454232413037384138384537",
        /*expectedHexProof*/ "80870F1B559F64693E594356B375C554F6E72FC8",
        /*expectedHexServerSalt*/ "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443",
        /*expectedHexServerPublicKey*/ "35464646374337314146444330384434333143443430304438384330424633444545414131353345423135423646383846364342463932424339414538304445383937383946463733323542313236364535343741373645433444424233313542373343324236464545413146303833373944453641353545394542314434354541453544303931304630313630433141414646333330423544454333334646423837303535423641303138434444423534443341373134434345383842433442384338333343444135303938344630463131383234343635444534454636423034423641384638373134304642433738423544454232413037384138384537",
        /*expectedDigitServerPublicKey*/ "67412082924434217936704877428825622694686497037198665603065437357867355004168202158030753494833957466589335990971910391503617589244315312226035694202361533433446546724578783817512260046992516302520544970979390659382993710736885170302085434051259003840601287227647617229353036005542187753985936062438663948519");
}
