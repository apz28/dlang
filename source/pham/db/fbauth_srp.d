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
import std.typecons : Flag, No, Yes;

import pham.utl.utlobject : bytesFromHexs, bytesToHexs;
import pham.cp.biginteger;
import pham.cp.auth_rsp;
import pham.db.fbauth;

nothrow @safe:

class FbAuthSrp : FbAuth
{
nothrow @safe:

public:
    this()
    {
        this._authClient = new AuthClient(AuthParameters(DigestAlgorithm.sha1, fbPrime),
            digitsToBigInteger(fbK));
    }

    version (unittest)
    this(BigInteger ephemeralPrivate)
    {
        import pham.utl.utltest;

        this._authClient = new AuthClient(AuthParameters(DigestAlgorithm.sha1, fbPrime),
            digitsToBigInteger(fbK), ephemeralPrivate);

		dgFunctionTrace("N:          ", this._authClient.N);
		dgFunctionTrace("g:          ", this._authClient.g);
		dgFunctionTrace("k:          ", this._authClient.k);
		dgFunctionTrace("PrivateKey: ", this._authClient.ephemeralPrivate);
		dgFunctionTrace("PublicKey:  ", this._authClient.ephemeralPublic);
    }

    final override ubyte[] getAuthData(scope const(char)[] userName, scope const(char)[] userPassword, ubyte[] serverAuthData)
    {
        ubyte[] serverAuthSalt, serverAuthPublicKey;
        if (!parseServerAuthData(serverAuthData, serverAuthSalt, serverAuthPublicKey))
            return null;

        auto serverPublicKey = getServerAuthPublicKey(serverAuthPublicKey);
        _premasterKey = _authClient.calculatePremasterKey(userName, userPassword, serverAuthSalt, serverPublicKey);
        _proof = calculateProof(userName, userPassword, serverAuthSalt, serverPublicKey);
        return cast(ubyte[])bytesToHexs(_proof);
    }

    static BigInteger getServerAuthPublicKey(scope const(ubyte)[] serverAuthPublicKey) pure
    {
        return hexCharsToBigInteger(serverAuthPublicKey);
    }

    final override size_t maxSizeServerAuthData(out size_t maxSaltLength) const pure
    {
        maxSaltLength = fbSaltLength * 2;
        // ((fbSaltLength + 1) * 2) + ((fbKeyLength + 1) * 2)
        return (fbSaltLength + fbKeyLength + 2) * 2;  //+2 for leading size data
    }

    final override const(ubyte)[] privateKey() const
    {
        return _authClient.ephemeralPrivateKey();
    }

    final override const(ubyte)[] publicKey() const
    {
        return _authClient.ephemeralPublicKey();
    }

    final override const(ubyte)[] sessionKey() const
    {
        return _sessionKey;
    }

    @property final override bool isSymantic() const
    {
        return true;
    }

    @property final override string name() const
    {
        return "Srp";
    }

    @property final override string sessionKeyName() const
    {
        return "Symmetric";
    }

protected:
    final ubyte[] calculateProof(scope const(char)[] userName, scope const(char)[] userPassword,
        scope const(ubyte)[] salt, const BigInteger serverPublicKey)
	{
        auto parameters = _authClient.parameters;
        auto hasher = parameters.hasher;


        /* .NET
		var K = GetClientSessionKey(user, password, salt, serverPublicKey);

		var n1 = BigIntegerFromByteArray(ComputeHash(BigIntegerToByteArray(N)));
		var n2 = BigIntegerFromByteArray(ComputeHash(BigIntegerToByteArray(g)));

		n1 = BigInteger.ModPow(n1, n2, N);
		n2 = BigIntegerFromByteArray(ComputeHash(Encoding.UTF8.GetBytes(user)));

		var M = ComputeHash(BigIntegerToByteArray(n1),
			BigIntegerToByteArray(n2),
			salt,
			BigIntegerToByteArray(PublicKey),
			BigIntegerToByteArray(serverPublicKey),
			K);
        */
        auto K = _authClient.digest(_premasterKey);
		auto n1 = bytesToBigInteger(_authClient.digest(_authClient.N));
		auto n2 = bytesToBigInteger(_authClient.digest(_authClient.g));

		n1 = modPow(n1, n2, _authClient.N);
		n2 = bytesToBigInteger(_authClient.digest(userName));

        AuthDigestResult hashTemp = void;
        auto M = hasher.begin()
            .digest(bigIntegerToBytes(n1))
            .digest(bigIntegerToBytes(n2))
            .digest(salt)
            .digest(bigIntegerToBytes(_authClient.ephemeralPublic))
            .digest(bigIntegerToBytes(serverPublicKey))
            .digest(K)
            .finish(hashTemp).dup;

        _sessionKey = K;
        return M;

        version (TraceAuthRSP)
        {
		dgWriteln("ClientProof.ComputeHash.n1(2):             ", n1.toString());
		dgWriteln("ClientProof.ComputeHash.n2(2):             ", n2.toString());
		dgWriteln("ClientProof.ComputeHash.n2(2).ComputeHash: ", hasher.begin()
            .digest(AuthParameters.asBytes(userName))
            .finish(hashTemp));
		dgWriteln("ClientProof.SessionKey:                    ", premasterKeyDigest);
		dgWriteln("ClientProof.Proof:                         ", _proof);
		dgWriteln("ClientProof.result:                        ", _proof);
        }
    }

    override void doDispose(bool disposing) nothrow @safe
    {
        super.doDispose(disposing);
        if (_authClient !is null)
        {
            _authClient.disposal(disposing);
            _authClient = null;
        }
        _premasterKey.setZero();
        _proof = null;
        _sessionKey = null;
    }

private:
    AuthClient _authClient;
    BigInteger _premasterKey;
    ubyte[] _proof;
    ubyte[] _sessionKey;
}


// Any below codes are private
private:


enum fbK = "1277432915985975349439481660349303019122249719989";
enum fbN = "161854874649776085868045952190159031555772097014435707776279513538616175047026058065927714606879676219064271341818754038806823814541886861147177045257236811627035155212310813305487929926508522581710604504792711726648563877865328333166885998671854094528177699206377434633696300213499023964016345755132798642663";
enum fbKeyLength = 128;
enum fbSaltLength = 32;

immutable PrimeGroup fbPrime;

shared static this()
{
    fbPrime = immutable PrimeGroup(
        2,
        "E67D2E99 4B2F900C 3F41F08F 5BB2627E D0D49EE1 FE767A52 EFCD565C D6E76881
         2C3E1E9C E8F0A8BE A6CB13CD 29DDEBF7 A96D4A93 B55D488D F099A15C 89DCB064
         0738EB2C BDD9A8F7 BAB561AB 1B0DC1C6 CDABF303 264A08D1 BCA932D1 F1EE428B
         619D970F 342ABA9A 65793B8B 2F041AE5 364350C1 6F735F56 ECBCA87B D57B29E7",
        fbSaltLength,
        fbKeyLength);
}

nothrow @safe unittest // PrimeGroup
{
    import pham.utl.utltest;
    dgWriteln("unittest db.fbauth_srp.PrimeGroup");

    assert(fbPrime.N.toString() == fbN);
    assert(fbPrime.g.toString() == "2");
    assert(fbPrime.padSize == fbKeyLength);
}

version (unittest)
{
    import std.conv : to;
    import pham.utl.utltest;

    auto testUserName = "SYSDBA";
    auto testUserPassword = "masterkey";

    void testCheck(const(char)[] digitPrivateKey,
        const(char)[] digitExpectedPublicKey,
        const(char)[] serverHexAuthData,
        const(char)[] expectedHexProof,
        const(char)[] expectedHexServerSalt,
        const(char)[] expectedHexServerPublicKey,
        const(char)[] expectedDigitServerPublicKey,
        size_t line = __LINE__)
    {
        auto privateKey = digitsToBigInteger(digitPrivateKey);
        auto serverAuthData = bytesFromHexs(serverHexAuthData);
        auto client = new FbAuthSrp(privateKey);
        auto proof = client.getAuthData(testUserName, testUserPassword, serverAuthData);

        assert(client._authClient.ephemeralPublic.toString() == digitExpectedPublicKey,
            "digitExpectedPublicKey(" ~ to!string(line) ~ "): " ~ client._authClient.ephemeralPublic.toString() ~ " ? " ~ digitExpectedPublicKey);
        assert(bytesToHexs(client.serverPublicKey) == expectedHexServerPublicKey,
            "expectedHexServerPublicKey(" ~ to!string(line) ~ "): " ~ bytesToHexs(client.serverPublicKey) ~ " ? " ~ expectedHexServerPublicKey);
        assert(bytesToHexs(client.serverSalt) == expectedHexServerSalt,
            "expectedHexServerSalt(" ~ to!string(line) ~ "): " ~ bytesToHexs(client.serverSalt) ~ " ? " ~ expectedHexServerSalt);
        auto serverPublicKey = FbAuthSrp.getServerAuthPublicKey(client.serverPublicKey);
        assert(serverPublicKey.toString() == expectedDigitServerPublicKey,
            "expectedDigitServerPublicKey(" ~ to!string(line) ~ "): " ~ serverPublicKey.toString() ~ " ? " ~ expectedDigitServerPublicKey);
        assert(cast(char[])proof == expectedHexProof,
            "expectedHexProof(" ~ to!string(line) ~ "): " ~ cast(char[])proof ~ " ? " ~ expectedHexProof);
    }
}

nothrow @safe unittest // FbAuthSrp
{
    import pham.utl.utltest;
    dgWriteln("unittest db.fbauth_srp.FbAuthSrp");

    testCheck(
        /*digitPrivateKey*/ "264905762513559650080771073972109248903",
        /*digitExpectedPublicKey*/ "20683020699665853524089952214242729025570102331355286896164651135690756690875771106556553465927252488139803212504773984793490588986767319872337272030442815731428721361389194577481083428832457789266753718602245677204767791176476438551576288962556819987630078684529566279195237212923198916151796921004472200100",
        /*serverHexAuthData*/ "400043414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443000141454444374133423436343346313545333943364232453835333941334442464336433231444530444542303632354433463430374337453234384435303343333832413442353646334138323131413943393443433044343137333334303731333636443833323732413031433433463539363846424130423842363446313344334437454637353042354246463536314238414630323645314333434234424345453330413931324541384236374337463935424231363642423331334337374343424533314538334546413438454634464339393442354234383543454137394142333139344343303542303032383739383946423138423539323542",
        /*expectedHexProof*/ "13B25FD696423778F29DEAA266F4B88C40CC6B7A",
        /*expectedHexServerSalt*/ "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443",
        /*expectedHexServerPublicKey*/ "41454444374133423436343346313545333943364232453835333941334442464336433231444530444542303632354433463430374337453234384435303343333832413442353646334138323131413943393443433044343137333334303731333636443833323732413031433433463539363846424130423842363446313344334437454637353042354246463536314238414630323645314333434234424345453330413931324541384236374337463935424231363642423331334337374343424533314538334546413438454634464339393442354234383543454137394142333139344343303542303032383739383946423138423539323542",
        /*expectedDigitServerPublicKey*/ "122794481691256336976092504484682159342073724919120490560325361482978121758107403785116811617321015749520781999274663407045551768201722343482077317182691516688493237430938639003996055723030390419024244864218313640971850213487122457987110730006824960154761449277369233202613446097587560665634914036217458037339");

    testCheck(
        /*digitPrivateKey*/ "270171508735298645974390825330911403670",
        /*digitExpectedPublicKey*/ "90601182554443833646240732529595335357718206973596771208700719399606004823938813613233818285223851022085728368640419211513647539405419744687959875936482152456343610020609119700028320381695401814333844670102621019521662806635505332344045469300581224121204528440759728394449869884840811226751426023025109979600",
        /*serverHexAuthData*/ "400043414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443000135464646374337314146444330384434333143443430304438384330424633444545414131353345423135423646383846364342463932424339414538304445383937383946463733323542313236364535343741373645433444424233313542373343324236464545413146303833373944453641353545394542314434354541453544303931304630313630433141414646333330423544454333334646423837303535423641303138434444423534443341373134434345383842433442384338333343444135303938344630463131383234343635444534454636423034423641384638373134304642433738423544454232413037384138384537",
        /*expectedHexProof*/ "80870F1B559F64693E594356B375C554F6E72FC8",
        /*expectedHexServerSalt*/ "43414137364546413943383943443734433130363737303145434232424332363635393136423946384145383143353537453543333044383939463236434443",
        /*expectedHexServerPublicKey*/ "35464646374337314146444330384434333143443430304438384330424633444545414131353345423135423646383846364342463932424339414538304445383937383946463733323542313236364535343741373645433444424233313542373343324236464545413146303833373944453641353545394542314434354541453544303931304630313630433141414646333330423544454333334646423837303535423641303138434444423534443341373134434345383842433442384338333343444135303938344630463131383234343635444534454636423034423641384638373134304642433738423544454232413037384138384537",
        /*expectedDigitServerPublicKey*/ "67412082924434217936704877428825622694686497037198665603065437357867355004168202158030753494833957466589335990971910391503617589244315312226035694202361533433446546724578783817512260046992516302520544970979390659382993710736885170302085434051259003840601287227647617229353036005542187753985936062438663948519");
}
