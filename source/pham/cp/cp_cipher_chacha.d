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

module pham.cp.cp_cipher_chacha;

import std.algorithm.mutation : swap;
import std.string : representation;

import pham.utl.utl_bit : bytesToNative, nativeToBytes;
import pham.utl.utl_disposable : DisposingReason;
import pham.cp.cp_cipher;

nothrow @safe:

class CipherChaCha20 : Cipher
{
nothrow @safe:

public:
    enum blockSize = 64;
    enum blockIntSize = blockSize / 4;

    /* Initial ChaCha20 state for 32 bit counter
     * cccccccc  cccccccc  cccccccc  cccccccc
     * kkkkkkkk  kkkkkkkk  kkkkkkkk  kkkkkkkk
     * kkkkkkkk  kkkkkkkk  kkkkkkkk  kkkkkkkk
     * bbbbbbbb  nnnnnnnn  nnnnnnnn  nnnnnnnn
     * c=constant k=key b=blockcount n=nonce
     */
    struct Block
    {
    nothrow @safe:

        union
        {
            uint[blockIntSize] ints;
            ubyte[blockSize] bytes;
        }
    }

    enum nonceSizeX = 24;

public:
	this(scope const(ubyte)[] key, scope const(ubyte)[] nonce, uint counter32,
        int rounds = 0) pure
    in
    {
        import std.conv : to;
        assert(key.length == CipherChaChaKey.keySize128 || key.length == CipherChaChaKey.keySize256, key.length.to!string());
        assert(nonce.length == CipherChaChaKey.nonceSizeCounter32 || nonce.length == CipherChaChaKey.nonceSizeCounter64, nonce.length.to!string());
		assert(CipherRawKey!ubyte.isValid(key));
		assert(CipherRawKey!ubyte.isValid(nonce));
    }
    do
    {
        // XChaCha20 uses the ChaCha20 core to mix 16 bytes of the nonce into a
		// derived key, allowing it to operate on a nonce of 24 bytes. See
		// draft-irtf-cfrg-xchacha-01, Section 2.3.
        version(none)
        if (nonce.length == nonceSizeX)
        {
		    initKey[] = hChaCha20(_parameters.privateKey.chacha.key, _parameters.privateKey.chacha.nonce[0..16]);
		    initNonce[0..4] = 0;
		    initNonce[4..12] = _parameters.privateKey.chacha.nonce[16..24];
        }

        auto k = CipherChaChaKey(cast(uint)(key.length * 8), key, nonce, counter32, rounds);
        this(CipherKey(k));
    }

	this(scope const(ubyte)[] key, scope const(ubyte)[] nonce, ulong counter64,
        int rounds = 0) pure
    in
    {
        import std.conv : to;
        assert(key.length == CipherChaChaKey.keySize128 || key.length == CipherChaChaKey.keySize256, key.length.to!string());
        assert(nonce.length == CipherChaChaKey.nonceSizeCounter32 || nonce.length == CipherChaChaKey.nonceSizeCounter64, nonce.length.to!string());
		assert(CipherRawKey!ubyte.isValid(key));
		assert(CipherRawKey!ubyte.isValid(nonce));
    }
    do
    {
        auto k = CipherChaChaKey(cast(uint)(key.length * 8), key, nonce, counter64, rounds);
        this(CipherKey(k));
    }

	this(CipherKey key) pure
    in
    {
        assert(key.kind == CipherKeyKind.chacha);
		assert(key.chacha.isValid());
    }
    do
    {
        this._parameters = CipherParameters(key);
        this.initKey();
        this.initNonce();
	}

    final override ubyte[] decrypt(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        if (_overflow)
            return null;

		const resultLength = input.length;
        if (output.length < resultLength)
            output.length = resultLength;

        return resultLength != 0 ? process(input, output) : null;
    }

    final override ubyte[] encrypt(scope const(ubyte)[] input, return ref ubyte[] output)
    {
        if (_overflow)
            return null;

		const resultLength = input.length;
        if (output.length < resultLength)
            output.length = resultLength;

        return resultLength != 0 ? process(input, output) : null;
    }

    @property final override bool isSymantic() const @nogc pure
    {
        return true;
    }

    @property final override string name() const pure
    {
        return "ChaCha20";
    }

	@property final bool overflow() const @nogc pure
    {
		return _overflow;
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        _input.ints[] = 0;
        _kStream.ints[] = 0;
        _kStreamLeft = 0;
        super.doDispose(disposingReason);
    }

private:
    final void initKey() pure
    {
        _kStreamLeft = 0;
        _overflow = false;
        _rounds = _parameters.privateKey.chacha.rounds;
        _counterSize = _parameters.privateKey.chacha.counterSize;

        const(ubyte)[] key = _parameters.privateKey.chacha.key;
        const keyLength = key.length;
        assert(keyLength == CipherChaChaKey.keySize128 || keyLength == CipherChaChaKey.keySize256);

        _input.ints[4] = bytesToNative!uint(key[0..4]);
        _input.ints[5] = bytesToNative!uint(key[4..8]);
        _input.ints[6] = bytesToNative!uint(key[8..12]);
        _input.ints[7] = bytesToNative!uint(key[12..16]);

        // 256 bit?
        if (keyLength == 32)
            key = key[16..$];

        _input.ints[8] = bytesToNative!uint(key[0..4]);
        _input.ints[9] = bytesToNative!uint(key[4..8]);
        _input.ints[10] = bytesToNative!uint(key[8..12]);
        _input.ints[11] = bytesToNative!uint(key[12..16]);

        const constants = keyLength == 32 ? sigma.representation : tau.representation;
        _input.ints[0] = bytesToNative!uint(constants[0..4]);
        _input.ints[1] = bytesToNative!uint(constants[4..8]);
        _input.ints[2] = bytesToNative!uint(constants[8..12]);
        _input.ints[3] = bytesToNative!uint(constants[12..16]);
    }

    final void initNonce() pure
    {
        const(ubyte)[] nonce = _parameters.privateKey.chacha.nonce;
        const nonceLength = nonce.length;

        final switch (_counterSize) with (CipherChaChaKey.CounterSize)
        {
            case counter32:
                assert(nonceLength == CipherChaChaKey.nonceSizeCounter32);
                const counter32 = _parameters.privateKey.chacha.counter32;
                _input.ints[12] = counter32;
                _input.ints[13] = bytesToNative!uint(nonce[0..4]);
                _input.ints[14] = bytesToNative!uint(nonce[4..8]);
                _input.ints[15] = bytesToNative!uint(nonce[8..12]);
                break;
            case counter64:
                assert(nonceLength == CipherChaChaKey.nonceSizeCounter64);
                const counter64 = _parameters.privateKey.chacha.counter64;
                _input.ints[12] = cast(uint)(counter64 & 0xFFFF_FFFF);
                _input.ints[13] = cast(uint)(counter64 >> 32);
                _input.ints[14] = bytesToNative!uint(nonce[0..4]);
                _input.ints[15] = bytesToNative!uint(nonce[4..8]);
                break;
        }
    }

    final ubyte[] process(scope const(ubyte)[] input, ubyte[] output) @nogc pure
    in
    {
        assert(input.length != 0);
        assert(output.length >= input.length);
    }
    do
    {
        ubyte[] resultOutput = output;
        size_t resultLength = 0;

        if (this._kStreamLeft)
        {
            const j = this._kStreamLeft > input.length ? input.length : this._kStreamLeft;
            foreach (i; 0..j)
            {
                output[i] = input[i] ^ this._kStream.bytes[blockSize - this._kStreamLeft];
                this._kStreamLeft--;
            }

            resultLength += j;
            output = output[j..$];
            input = input[j..$];
            if (input.length == 0)
                return resultOutput[0..resultLength];

            // Must be zero at this point
            assert(this._kStreamLeft == 0);
        }

        Block buf;
        for (;;)
        {
            chacha20Block(buf, this._input, this._rounds);

            final switch (this._counterSize) with (CipherChaChaKey.CounterSize)
            {
                case counter32:
                    if (++this._input.ints[12] == 0)
                    {
                        this._overflow = true;
                        return resultOutput[0..resultLength];
                    }
                    break;
                case counter64:
                    if (++this._input.ints[12] == 0 && ++this._input.ints[13] == 0)
                    {
                        this._overflow = true;
                        return resultOutput[0..resultLength];
                    }
                    break;
            }

            if (input.length <= blockSize)
            {
                foreach (i; 0..input.length)
                    output[i] = input[i] ^ buf.bytes[i];
                this._kStreamLeft = blockSize - input.length;
                for (size_t i = input.length; i < blockSize; ++i)
                    this._kStream.bytes[i] = buf.bytes[i];
                resultLength += input.length;
                return resultOutput[0..resultLength];
            }

            foreach (i; 0..blockSize)
                output[i] = input[i] ^ buf.bytes[i];

            resultLength += blockSize;
            output = output[blockSize..$];
            input = input[blockSize..$];
        }

        //return resultOutput[0..resultLength];
        assert(0, "Unreachable");
    }

    static void chacha20Block(ref Block output, ref const(Block) input, const(int) rounds) @nogc pure
    {
        Block x;
        x.ints[0..blockIntSize] = input.ints[0..blockIntSize];

        void quarterRound(const(size_t) a, const(size_t) b, const(size_t) c, const(size_t) d) @nogc pure
        {
            x.ints[a] += x.ints[b]; x.ints[d] = rol(x.ints[d] ^ x.ints[a], 16);
            x.ints[c] += x.ints[d]; x.ints[b] = rol(x.ints[b] ^ x.ints[c], 12);
            x.ints[a] += x.ints[b]; x.ints[d] = rol(x.ints[d] ^ x.ints[a],  8);
            x.ints[c] += x.ints[d]; x.ints[b] = rol(x.ints[b] ^ x.ints[c],  7);
        }

        for (int i = rounds; i > 0; i -= 2)
        {
            quarterRound(0, 4,  8, 12);
            quarterRound(1, 5,  9, 13);
            quarterRound(2, 6, 10, 14);
            quarterRound(3, 7, 11, 15);
            quarterRound(0, 5, 10, 15);
            quarterRound(1, 6, 11, 12);
            quarterRound(2, 7,  8, 13);
            quarterRound(3, 4,  9, 14);
        }

        foreach (i; 0..blockIntSize)
        {
            x.ints[i] += input.ints[i];
            output.ints[i] = x.ints[i];
        }
    }

	pragma(inline, true)
	static uint rol(uint v, int c) @nogc pure
    {
		return (v << c) | (v >> (uint.sizeof * 8 - c));
    }

private:
    static immutable string sigma = "expand 32-byte k";
    static immutable string tau   = "expand 16-byte k";

    Block _input;
    Block _kStream;
    size_t _kStreamLeft;
    int _rounds;
    CipherChaChaKey.CounterSize _counterSize;
    bool _overflow;
}


// Any below codes are private
private:

unittest // CipherChaCha20
{
	import std.conv : to;
    import pham.utl.utl_convert : bytesFromHexs;

	static struct TestCase
    {
		string nonce;
		string key;
		string input;
		string output;
    }

	static void test32(TestCase testCase, in int fromLine = __LINE__)
    {
        auto cipher = new CipherChaCha20(bytesFromHexs(testCase.key), bytesFromHexs(testCase.nonce), uint(0));
		auto input = bytesFromHexs(testCase.input);
		auto expect = bytesFromHexs(testCase.output);
		ubyte[] output;
		const result = cipher.encrypt(input, output);
		//dgWriteln(expect.dgToHex());
		//dgWriteln(result.dgToHex());
		assert(result == expect, "From line: " ~ fromLine.to!string());
    }

	test32(TestCase(
		/* nonce */"1733d194b3a2b6063600fe3f",
		/* key */"b6a3a89de64abf3aae9cf1a207c768101e80e472925d16ce8f02e761573dac82",
		/* input */"",
		/* output */"",
	));

	test32(TestCase(
		/* nonce */"ddfa69041ecc3feeb077cf45",
		/* key */"2be077349f80bf45faa1f427e81d90dbdc90a1d8d4212c1dacf2bd870000bfdf",
		/* input */"23dbad0780",
		/* output */"415a3e498d",
	));

	test32(TestCase(
		/* nonce */"496b2a516daff98da5a23653",
		/* key */"254c12e973a3d14fbbf7457964f0d5ee5d18c42913cf9a3c67a3944c532c2c7c",
		/* input */"f518831fab69c054a6",
		/* output */"cfe40f63f81391484b",
	));

	test32(TestCase(
		/* nonce */"9e7a69ca17672f6b209285b7",
		/* key */"205082fc0b41a45cd085527d9d1c0a16410b47152a743436faa74ae67ae60bca",
		/* input */"805fad1d62951537aeed9859",
		/* output */"47bd303f93c3ce04bce44710",
	));

	test32(TestCase(
		/* nonce */"b33dedcd7f0a77359bdeae06",
		/* key */"ef2d6344a720e4a58f2ac10f159ab76314e37d3316bf2fb857bc043127927c67",
		/* input */"f4e8a7577affb841cf48392cf5df",
		/* output */"f445c0fb7e3d5bfdab47090ddee6",
	));

	test32(TestCase(
		/* nonce */"b1508a348092cc4ace14608d",
		/* key */"a831bd347ef40828f9198b9d8396f54d48435831454aa734a274e10ddcc7d429",
		/* input */"1179b71ec4dc34bd812f742b5a0b27",
		/* output */"cc7f80f333c647d6e592e4f7ecc834",
	));

	test32(TestCase(
		/* nonce */"034775c821c58891a6e88cac",
		/* key */"ed793ce92b1689ce66836a117f65dcec981dc85b522f5dffbb3e1f172f3f7750",
		/* input */"7bd94943d55392d0311c413ac755ce0347872ba3",
		/* output */"c43665de15136af232675d9d5dbbeca77f3c542a",
	));

	test32(TestCase(
		/* nonce */"cb55869aa56e9d6e5e70ad5d",
		/* key */"b3d542358ffd7b1ff8ab3810ece814729356d0edbd63e66006d5e5e8a223a9ee",
		/* input */"1505f669acc5ad9aaa0e993ba8c24e744d13655e1f",
		/* output */"26cad1ccf4cf4c49b267ab7be10bc2ffa3ba66bc86",
	));

	test32(TestCase(
		/* nonce */"a42c203f86fc63000ea16072",
		/* key */"d6b18ae2473d3be8ca711267ffbc77b97644f6a2b4791d31d0910d180c6e1aec",
		/* input */"20070523ddb4ebf0d5f20fd95aacf47fb269ebadda6879638a",
		/* output */"5ce972624cb2b7e7c28f5b865ba08c887911b4f5e361830a4b",
	));

	test32(TestCase(
		/* nonce */"ea7186cf2fdf728d8a535a8b",
		/* key */"bba26ce4efb56ad06b96e2b02d0cdd549ad81588a9306c421e0f5b0175ae4b25",
		/* input */"d10f8050c1186f92e26f351db36490d82ea677498562d8d4f487a0a4058adf",
		/* output */"f30c11bc553b2baf6870760d735680897c9fee168f976b2a33ef395fdbd4fc",
	));

	test32(TestCase(
		/* nonce */"3a98bed189a35a0fe1c726fa",
		/* key */"a76d5c79dcaab18c9a3542a0272eea95c45382122f59bcaa10e8910371d941f6",
		/* input */"e88dc380b7d45a4a762c34f310199587867516fac4a2634022b96a9f862e17714d17",
		/* output */"aac98ba3821399e55a5eab5862f7f1bfc63637d700125878c2b17151f306c9aec80e",
	));

	test32(TestCase(
		/* nonce */"b8f4f598731d183f2e57f45b",
		/* key */"f78c6fa82b1ab48d5631e0e0598aad3dbad1e4b338fbf6759d7094dbf334dbc3",
		/* input */"b0fcf0a731e2902787309697db2384e1cda07b60002c95355a4e261fb601f034b2b3",
		/* output */"b6c8c40ddda029a70a21c25f724cc90c43f6edc407055683572a9f5e9690a1d571bb",
	));

	test32(TestCase(
		/* nonce */"18ae8972507ebe7e7691817d",
		/* key */"a0076c332ba22e4a462f87a8285e7ba43f5e64be91651c377a23dcd28095c592",
		/* input */"cf9ec6fa3f0a67488adb5598a48ed916729a1e416d206f9675dfa9fd6585793f274f363bbca348b3",
		/* output */"bb7ed8a199aa329dcd18736ce705804ffae8c3e2ba341ae907f94f4672d57175df25d28e16962fd6",
	));

	test32(TestCase(
		/* nonce */"de8131fd263e198b99c7eb0b",
		/* key */"2e4c1a78e255ab2743af4a8101ab0b0ae02ce69dd2032b47e818eedf935b858b",
		/* input */"be9a8211d68642310724eda3dd02f63fcc03a101d9564b0ecee6f4ecececcb0099bb26aabee46b1a2c0416b4ac269e",
		/* output */"3152f317cf3626e26d02cff9392619ea02e22115b6d43d6dd2e1177c6bb3cb71c4a90c3d13b63c43e03605ec98d9a1",
	));

	test32(TestCase(
		/* nonce */"f62fb0273e6110a5d8228b21",
		/* key */"3277fc62f46cf0ced55ef4a44f65962f6e952b9ff472b542869cb55b4f78e435",
		/* input */"495343a257250f8970f791f493b89d10edba89806b88aaaeb3b5aefd078ba7b765746164bce653f5e6c096dd8499fb76d97d77",
		/* output */"62c01f426581551b5b16e8b1a3a23c86bcdd189ab695dbea4bf811a14741e6ebbb0261ef8ae47778a6be7e0ef11697b891412c",
	));

	test32(TestCase(
		/* nonce */"637ab99d4802f50f56dfb6f2",
		/* key */"8f7a652b5d5767fe61d256aa979a1730f1fffcae98b68e9b5637fe1e0c45eab4",
		/* input */"e37fbbd3fe37ce5a99d18e5dcb0dafe7adf8b596528708f7d310569ab44c251377f7363a390c653965e0cb8dd217464b3d8f79c1",
		/* output */"b07d4c56fb83a49e8d9fc992e1230bb5086fecbd828cdbc7353f61b1a3cec0baf9c5bf67c9da06b49469a999ba3b37916ec125be",
	));

	test32(TestCase(
		/* nonce */"38ecdfc1d303757d663c3e9a",
		/* key */"e7d8148613049bdefab4482a44e7bdcb5edc5dad3ed8449117d6d97445db0b23",
		/* input */"9efab614388a7d99102bcc901e3623d31fd9dd9d3c3338d086f69c13e7aa8653f9ce76e722e5a6a8cbbbee067a6cb9c59aa9b4b4c518bbed",
		/* output */"829d9fe74b7a4b3aeb04580b41d38a156ffbebba5d49ad55d1b0370f25abcd41221304941ad8e0d5095e15fbd839295bf1e7a509a807c005",
	));

	test32(TestCase(
		/* nonce */"1c52e2c7b4995479d76c94c7",
		/* key */"74e7fc53bf534b9a3441615f1494c3a3727ca0a81123249399ecae435aeb6d21",
		/* input */"03b5d7ab4bd8c9a4f47ec122cbeb595bd1a0d58de3bb3dcc66c4e288f29622d6863e846fdfb27a90740feb03a4761c6017250bc0f129cc65d19680ab9d6970",
		/* output */"83db55d9eb441a909268311da67d432c732ad6bda0a0dae710d1bce040b91269deb558a68ced4aa5760ca0b9c5efc84e725f297bdbdadbc368bea4e20261c5",
	));

	test32(TestCase(
		/* nonce */"a1f0411d78773b7ca5ee9169",
		/* key */"393e211f141d26562c7cfc15c5ccfe21c58456a9060560266bc0dcdab010c8f2",
		/* input */"2f4da518578a2a82c8c855155645838ca431cdf35d9f8562f256746150580ca1c74f79b3e9ae78224573da8b47a4b3cc63fbed8d4e831a6b4d796c124d87c78a66e5",
		/* output */"6fc086ded3d1d5566577ccd9971e713c1126ec52d3894f09ab701116c7b5abda959cbb207f4468eb7b6a6b7e1b6d2bc6047f337499d63522f256ee751b91f84f70b6",
	));

	test32(TestCase(
		/* nonce */"2c029f74b0da21a052228c64",
		/* key */"b0e7aca1a10e7a56b913af52080ca3cb746d7ae039ca3b5c07acb285c0afb503",
		/* input */"55739a1738b4a4028021b21549e2661b050e3d830ad9a56f57bfcaca3e0f72051b9ca92411840061083e5e45124d8425061ab26c632ac7852118411ac80026da946357c630f27225",
		/* output */"8051bf98f8f2617e159ba205a9342ab700973dd045e09321805eed89e419f37f3211c5aa82666b9a097270babc26d3bfe0c990fe245ae982a31f23cfbf6156b5c8cfb77f340e2bf5",
	));

	test32(TestCase(
		/* nonce */"a86bc1234ecdd19fcb4e22cb",
		/* key */"4a4094b698f1b586ff1bfd10544ea81309e521ab64d74374f1b33109f2876e68",
		/* input */"7ffd8d5970fdee613eeae531d1c673fd379d64b0b6bfedd010433b080b561038f7f266fa7e15d7d8e10d23f21b9d7724bb200b0f58b9250483e784f4a6555d09c234e8d1c549ebb76a8e",
		/* output */"c173617e36ea20ce04c490803b2098bd4f1ff4b31fdca1c51c6475ade83892c5f12731652d5774631d55ae2938617a5e9462bb6083328a23a4fba52de50ca9075586f2efc22aae56e3a8",
	));

	test32(TestCase(
		/* nonce */"296f5fd61962f7f39e3c039a",
		/* key */"c417a0eb1a42e06917239e44118a85293a52c8d0a2c9b0a884cab20a451a01af",
		/* input */"7a5766097562361cfaeac5b8a6175e1ceeeda30aec5e354df4302e7700ea48c505da9fdc57874da879480ecfea9c6c8904f330cbac5e27f296b33b667fea483348f031bef761d0b8e318a8132caa7a5943",
		/* output */"5e9fbf427c4f0fcf44db3180ea47d923f52bee933a985543622eff70e2b3f5c673be8e05cd7acbcadd8593da454c60d5f19131e61730a73b9c0f87e3921ee5a591a086446b2a0fadd8a4bc7b49a8e83764",
	));

	test32(TestCase(
		/* nonce */"6ee50ec741ec580e616fd9af",
		/* key */"bbf22a177cd285904dc4a28cda48a18ab0880c29397418888147d518ce2c3f63",
		/* input */"0777c02a2900052d9b79f38387d2c234108a2ad066cbf7df6ea6acc5a3f86b3d6156abb5b18ad4ecf79e171383a1897e64a95ecdbba6aa3f1c7c12fe31283629ff547cb113a826cb348a7c10507cc645fa2eb97b5f22e44d",
		/* output */"368c90db3464ba488340b1960e9f75d2c3b5b392bdd5622ff70e85e6d00b1e6a996ba3978ce64f8f2b5a9a90576c8f32b908233e15d2f443cccc98af87745c93c8056603407a3fb37ce0c1f8ab6384cc37c69c98bfecf337",
	));

	test32(TestCase(
		/* nonce */"79da06301d054827dc7cc172",
		/* key */"e8b7cd6028e9cbceb97a9be13715d63099c1fba0bf387789a90577dd63175c3e",
		/* input */"cf2dccbcfd781c030376f9019d841ca701cb54a1791f50f50bee0c2bf178182603a4712b5916eebd5001595c3f48283f1ba097ce2e7bf94f2b7fa957ce776e14a7a570093be2de386ececbd6525e72c5970c3e7d35974b8f0b831fbc",
		/* output */"7c92b8c75e6eb8675229660cedcb10334965a7737cde7336512d9eff846c670d1fa8f8a427ea4f43e66be609466711fd241ccff7d3f049bda3a2394e5aa2108abc80e859611dbd3c7ba2d044a3ececa4980dd65e823dd110fea7a548",
	));

	test32(TestCase(
		/* nonce */"eeb10ffc0ac64c4167bd4441",
		/* key */"c6913210b6032b8248b59ad2fe3e8fc86a0536691fa6aa285878dfa01935a2da",
		/* input */"e08a8949a1bfd6a8c1186b431b6ad59b106ae5552821db69b66dc03fbc4a2b970dcf9c7da4f5082572bc978f8ee27c554c8884b5a450b36d70453348cd6cac9b80c9900cf98a4088803f564bb1281d24507b2f61ba737c8145c71b50eb0f6dfc",
		/* output */"73d043acf9dcd758c7299bd1fd1f4100d61ff77d339e279bfbe6f9233b0d9afa24992a9c1c7a19545d469fdfb369c201322f6fe8c633fcdcffef31032bfb41b9fb55506e301d049fd447d61f974a713debeaed886f486a98efd3d6c3f25fbb30",
	));

	test32(TestCase(
		/* nonce */"570c03c2e1593b1e1ade7e60",
		/* key */"b5c2bad18345a9569b478b621ea556308f8fbf693de0f12dd2489d4b79c3f57d",
		/* input */"a0c302120111f00c99cff7d839cdf43207a7e2f73d5dd888daa00d84254db0e621a72493480420c9c61ce1cfc54188ff525bb7a0e6c1cd298f598973a1de9fd2d79a21401588775b0adbe261ba4e4f79a894d1bd5835b5924d09ba32ef03cb4bc0bd6eb4ee4274",
		/* output */"bc714bd7d8399beedc238f7ddeb0b99d94ad6bf8bf54548a3e4b90a76aa5673c91db6482591e8ff9126e1412bce56d52a4c2d89f22c29858e24482f177abacef428d0ae1779f0ae0778c44f9f02fe474da93c35c615b5fad29eca697978891f426714441317f2b",
	));

	test32(TestCase(
		/* nonce */"1fc84df4e7036ecf966796f4",
		/* key */"f4127b0d89473f68b48f82c7a0c60f82eb3112c5d71667e493ef36406cb9af26",
		/* input */"ebce290c03c7cb65d053918ba2da0256dc700b337b8c124c43d5da4746888ca78387feea1a3a72c5e249d3d93a1907977dd4009699a15be5da2ca89c60e971c8df5d4553b61b710d92d3453dea595a0e45ae1e093f02ea70608b7b32f9c6aadc661a052f9b14c03ea0117a3192",
		/* output */"cbb8c4ec827a1123c1141327c594d4a8b0b4a74b0008115bb9ec4275db3a8e5529a4f145551af29c473764cbaa0794b2d1eb1066f32a07fd39f5f3fe51498c46fba5310ae7c3664571d6a851e673ded3badc25e426f9c6038724779aa6d2d8ec3f54865f7df612e25575635ab5",
	));

	test32(TestCase(
		/* nonce */"1b463e8d60c3057eddafbb3b",
		/* key */"c917b9f9f79bf89ac9bbec7d7beae5e755ab4a9bbef6ef90906d9ba11a9bf6b9",
		/* input */"275c97de985aa265332065ccce437770b110737a77dea62137a5d6cb62e9cb8b504d34334a58a71aba153d9b86f21377467b2fafaf54829331bf2ce0009acb37842b7a4b5f152aab650a393153f1ed479abc21f7a6fe205b9852ff2f7f3a0e3bfe76ca9770efada4e29e06db0569a99d08648e",
		/* output */"b225aa01d5c438d572deaea51ac12c0c694e0f9dc0ed2884a98e5e2943d52bb4692d7d8f12486de12d0559087e8c09e4f2d5b74e350838aa2bd36023032ccbcae56be75c6a17c59583d81a1fd60e305af5053ac89f753c9347f3040e48405232dc8428c49dcb3d9b899145f5b3bc955f34dbbe",
	));

	test32(TestCase(
		/* nonce */"f5331f87bae3fee4931e8ccb",
		/* key */"03491233e587027e8f98d6e95f406219b5c1215fe695c62ac900b246ba98da9f",
		/* input */"ceda15cfffd53ccebe31b5886facd863f6166e02ec65f46f54148860a5c2702e34fd204d881af6055952690cd1ffa8ba4d0e297cc165d981b371932adb935398c987baff335108c5e77f2e5dd5e1ca9a017bc376cbdbe3c0f45e079c212e8986b438444e79cd37927c1479f45c9e75b0076cc9f8679011",
		/* output */"a3f1c3f885583b999c85cd118e2ababfa5a2de0c8eb28aacc161b1efee89d8de36ddeb584174c0e92011b8d667cb64009049976082072e6262933dbf7b14839805e1face375b7cbb54f9828ba1ed8aa55634ec5d72b6351feff4d77a3a22b34203b02e096f5e5f9ae9ad6a9dd16c57ce6d94dcc8873d18",
	));

	test32(TestCase(
		/* nonce */"e83c55efea20e1df3a7e049a",
		/* key */"c179f4be8b4f555989f097bf1e6f315228e4410104dc26ff578f0ce1598a56a7",
		/* input */"799bb2d634406753416b3a2b67513293a0b3496ef5b2d019758dedaaac2edd72502fc4a375b3f0d4237bc16b0e3d47e7ddc315c6aef3a23fcae2eb3a6083bc7ac4fd1b5bf0025cc1cb266b40234b77db762c747d3a7b27956cf3a4cf72320fb60c0d0713fa60b37a6cb5b21a599e79d0f06a5b7201aeb5d2",
		/* output */"e84dfb3dbaac364085497aeabd197db852d3140c0c07f5f10e5c144c1fe26a50a9877649e88c6fe04283f4b7590a8d0d042ef577693f76f706e31c4979437590fe0ab03d89afb089d1be50ae173ea5458810372838eceac53bf4bac792735d8149e548efb432e236da92bf3168bbcf36f644c23efb478a4e",
	));

	test32(TestCase(
		/* nonce */"a02481d9aa80cd78fc5cc53d",
		/* key */"416e2802e3383ef16b4735f7fc4bc433978797d795459c4a13040806d8fd9912",
		/* input */"b2d060bd173955f44ee01b8bfcf0a6fad017c3517e4e8c8da728379f6d54471c955615e2b1effe4ce3d0139df225223c361be1cac416ade10a749c5da324563696dae8272577e44e8588cd5306bff0bfbdb32af3ac7cbc78be24b51baf4d5e47cf8f1d6b0a63ed9359da45c3e7297b2314028848f5816feab885e2",
		/* output */"ffa4aa66dd5d39694ae64696bfa96f771accef68f195456ad815751e25c47ed4f27b436f1b3e3fcaa3e0d04133b53559c100cd633ced3d4321fc56225c85d2443727bce40434455aa4c1f3e6768c0fe58ad88b3a928313d41a7629f1ce874d2c8bcf822ebdaebfd9d95a31bb62daab5385eb8eefe026e8cbf1ff7a",
	));

	test32(TestCase(
		/* nonce */"0f6b105381fd11dff3b6d169",
		/* key */"38b1360794e1cd55c173820fe668c2f7d52b366155b43cbbfcc9d344fdd3567d",
		/* input */"4f0171d7309493a349530940feece3c6200693f9cff38924114d53f723d090fffa3c80731b5ca989d3e924d1fa14266632cb9ab879e1a36df22dc9f8d1dadea229db72fded0c42187c38b9fa263c20e5fb5b4aa80eb90e8616e36d9b8c613b371c402343823184ecad3532058a46cf9e7ea5a9ecad043ac3028cbcc3f36d32",
		/* output */"88c773ff34b23e691e14018ba1b2bd48a4a6979b377eb0d68336ce6192dcd5177e6b4f1c4bea2df90af56b35fe2a1d6279d253c0194dcbca9bf136f92d69165b216e4c9d1ce6b3fbe40c71e32c3f4088de352732d0e2bad9c16fd0bb9bde3d6c30257ce063432d09f19da79d49aa7641124a6c9e3f09449e911edbae11a053",
	));

	test32(TestCase(
		/* nonce */"bdff905e73f198a8889a9f26",
		/* key */"5fe044529bbeadf9ac549f9e46004623eacd8267962c98ba6b5021c7e3f710ed",
		/* input */"8f8d9e18d3212bd20b96d75c06d1a63622fd83d13f79d542e45996135368772ea81511302a0d87e246dd346314cfe019bae8a5c97f567f12d82aca98dfea397c6a47dd0c419f1c609d9c52dcfcbe7eee68b2635954206ed592b7081442ce9ce3187d10ccd41cc856fb924b011f817c676c9419f52a2938c7af5f76755a75eb065411",
		/* output */"4e130c5df384b9c3c84aa38a744260735e93783da0337ade99f777e692c5ea276ac4cc65880b4ae9c3b96888760fdddb74bc2e2694bedf1ee6f14619c8015f951ba81b274b466e318d09defe80bdbed57bc213ac4631d2eb14c8e348181d60f6295ceee1e9231ae047830ef4778ff66146621b76974773b5d11c8e17a476450f46ef",
	));

	test32(TestCase(
		/* nonce */"e8398e304ff1a49a96db11f5",
		/* key */"19523b8388e5824b2c652d4bd76e8f7c63e84bfee5503a9d9b0988b868198d9f",
		/* input */"30d2379dd3ceae612182576f9acf6de505ab5a9445fe1a86ae75c5c29429e11c50fd9ec657b29b173a3763b1e171b5a7da1803ba5d64fccb2d32cb7788be194dbca00c3c91774c4c4c8ede48c1027d7cc8b387101a4fe5e44a1d9693b2f627626025072806083aadbced91c9711a0171f52ffb8ed5596cf34130022398c8a1da99c7",
		/* output */"b1e8da34ad0189038ee24673979b405ef73fdbdd6f376f800031d64005a4ebed51a37f2180571223848decbea6dd22b198ab9560d7edc047c5d69183dc69b5fca346911d25cb2a1a9f830dc6382ad0024e8c3eef3aa2d155abcfe43bff01956a5e20a862fbed5c5e8df8eed0601a120caac634b068314e221f175baa11ae29002bb9",
	));

	test32(TestCase(
		/* nonce */"5acafea5b4c13a750966a4c5",
		/* key */"5948bfabf69b8d826daaf7f7a28c2025adc0a4d78232dd2fc2b8fc2b4bd88983",
		/* input */"d9404ccdcc8ef128a1b1ace4f9f1669d274ec82aa914cac34b83ac00b236478fd6167e96ec658850c6c139eb0f6fc0dd7191ba9a39828032008f7f37eb9a8df9d6cdd54240e600efe7fc49a674000c5030d825b2c5c96d0f19b8ecdbf4eeb86d3e569c5e3131abc7d6359dd4255284ccacf150d42e7a899536d51ee6db329654a4581c5ac6e419",
		/* output */"c5534b5fb40b4834300e9577a9d87440c5272263d06e6aee84aa92cdf5d1b033145d336f26e5fe55c09a7e75753af93d0786dfc1cb435e86c67bd3ec8e766d0801b99e68691e2c3c3ffec539cf62e68285ea9027daa2716cd6f97e8eb7b9e266357a25eb2d4839a829508a6b7228f2832b3cd998f77597ae530430e6e4ecb53eb9efe456863a04",
	));

	test32(TestCase(
		/* nonce */"4658aa126c4f608885950dc1",
		/* key */"d6cc91149d552f60060c08d4bdfa0202f8f4d3ff174c14bf3c3fbf8875330808",
		/* input */"231765f832927461f338aceb0f4cf51fd8469348c69c549c1dec7333d4aa4968c1ed58b65ab3fe3d0562600a2b076d56fd9ef91f589752e0455dd1d2e614cacfc0d757a11a4a2264bd38f23d3cca108632201b4f6c3b06477467726dde0c2f3aee01d66d788247663f1d0e66b044da9393ede27b9905b44115b067914961bdade85a2eca2844e1",
		/* output */"1dd35f3f774f66d88cb7c2b23820ee078a093d0d85f86c4f103d869f93e2dbdd8a7cb8f101084fe1d7281a71754ec9aac5eb4fca8c365b24ed80e695caace1a8781a5a225938b50b8be96d0499752fdabd4f50d0b6ce396c6e2ca45308d1f2cc5a2a2361a8ca7a334e6ee62d466d74a1b0bf5b352f4ef6d8f8c589b733748bd3d7cda593243fab",
	));

	test32(TestCase(
		/* nonce */"f0709d1c67a388a02b4dc24e",
		/* key */"75974e4952a8070d4af28aaf5c825bc68067e0c5cebafb17b5711d65efd848f5",
		/* input */"e46841f12d98aeb7710b9162d342895a971b0e3a499886bbb6aa74dc744a28d89a54542b628acdc2f693cb7c03f73fc3b74069bc3f2d000a145fb8a806cdc7d6fa971da09a33b92851cc3d1f6f5646d7fa2b1d564876feefeb63b6e66dba1c0b86ca345235bb822e0f93132346840d2a3d6eb1b541178ea51affc7b31f8da02732cc4e5bcb5d8683ae0a91c9",
		/* output */"1dcbfd0bb2b905656c52bd7b1bcdad9b4d434ae9ac221a0d3a316115cdd4a463fa9b3444d2612a4e277d0dcd881fa6e80e59e5a54e35e1a14747aed31edf4ac24214f9d9c329ebe2157620b64efaded9976549bc4aa100d5c15be3f85f700f8a21dfe77590dfee2de9a23cc1ed1e44f32ebf68ca289b097bc13b42802dc7c75309c4afc25b5741839f7db3d5",
	));

	test32(TestCase(
		/* nonce */"8b7b06236d6c275b606ccaae",
		/* key */"8844d62973293a89efb4e332d4d5f32a1bc05e094cb605c87d8b4e8862708d79",
		/* input */"e98e4a9550bdd29e4106f0cc8669dcc646a69438408e9a72c7cdb9b9d437b5f7a13fcb197629541c55bca1f8972a80cd1c1f591a0e24f977cdeb84763eab2648e42286e6473ea95e3a6a43b07a32b6a6cd80fe007ba0cf7f5ac7e651431f5e72690ec52a7134f9757daf0d8eff6b831a229db4ab8288f6bbf81e16fedebe621fd1737c8792cfd15fb3040f4f6a4cbc1e",
		/* output */"5c69cf522c058790a3bc38979e172b60e71f7896d362d754edc1668d4f388b3fc0acdf40786d2f34886e107a142b1e724b9b9b171cb0e38fd78b35f8ac5269d74296c39c9f8628d848f57af9d8525a33f19021db2b9c64ba113171ebb3882075019ec7e77b51ce80b063ed41d48dad481d9536c030002a75d15c1c10ce0ec3ff17bc483f8416055a99b53035f4b6ea60",
	));

	test32(TestCase(
		/* nonce */"5896072b85daf5bd0d45758a",
		/* key */"a3eac94919880462a5cfaa9bdcad7038e182c605f3fff9f44b8e84a3c1ebc10a",
		/* input */"ce0f0d900dd0d31749d08631ec59f216a1391f66a73bae81d3b0e2919a461bc9a14d6a01b827e3bcb55bbccf27c1ed574157e6becd5cf47181a73c9d3e865ab48a20551027e560e965876b0e1a256bfa5cb5179bf54bd8ec65e5570e374b853b37bf4b3ef1ec612d288ebc19275fa88da9419e012f957f9b6a7e375b3377db0eb3619c731aebfeb0930772b4020d3a3e90723e72",
		/* output */"b06981b57fe184091ef9f8ccf522a5bcdb59bf9a68a3ddb817fdd999a6ecf81053a602141cf1b17017bae592b6b6e64756631a2b29a9e1b4f877c8b2ae30f71bc921e4f34b6f9cd8e587c57a30245f80e95005d0f18f5114400785140e6743da352d921fb4a74632a9c40115ad7706263ac9b41a11609fa0c42fc00f8d60931976162598df63ebad9496dd8943d25a03fa47475c",
	));

	test32(TestCase(
		/* nonce */"b88a8e097be7d884415830bb",
		/* key */"3cf9b5468d77b2c88f27c52c4c90a3d24f5dce06e859440c305ca30402dcea2f",
		/* input */"eccfd66bdc691478f354b8423d6a3f20932a1f591d8e6cefa734975fb8ee6881b6dc92c0d1d5ed54fd1999efd7f11ac697a1f130587dd895eb498c9a8fc7d1714c385ec156ecae3bdea2a3462834245e724531d0fedda2b77693a53ed7354b758e875b23cfc83219a091fb2076e7a88cd77f779ed96f8d81ffa3fe5059303ac706086494b9f2982f4f88a0c6fadc3748625004db",
		/* output */"925529047d4177b72bf50905ba77e47608815522c1829b24046e439d5451901257903a5409fb910373167e8b7f4fdfa543a477608ddfc11bbd1efc138366961463b9915b302a346b795dd593f6fcf4fa73529b6fe83079552aabbe99474a72806f59688d826675fa7f6649b9f5307e5028853c9821b8c4a1a0fc4bfdc7c8c78b25aeaba2b5821d17b36317381a3bd578917d2504",
	));

	test32(TestCase(
		/* nonce */"4a6e2a2e8a486d9ab66c96f9",
		/* key */"ff3b90583f17bec2b52861e253afb6b6eb8e2f093633cf38fb90df7f374be27a",
		/* input */"f0c7139c69413869bca980d7f192b2bc3f57e34ca4f26164e1a54a234e84e1aa285cc02cfbaef3dfba2dbb52a555ec1f6ef0e89d0b2f0bd1846e65b74444b5f003a7308965e67bed558689be2668ca10ca368fac072e0e4535a031af23b3c37c561e185872b86c9bceddb5c1199e43fb5f735384766d33710460b541b52d3f5b6c108c08e76724bcac7ad2d866a8bbeeea92a3d867660d2e",
		/* output */"d2c16c7a242b493038203daec65960de384c030eb698ef6a53c36eabb7556cbfa4770eaa8bc0a2b385ad97495eeb1c03ff4e6efcb804aefa81c177dc62700a9eefe6e8dd10cff5d43a2f47463cab5eb1ee260c3826cac9bfa070f1e0435541a89ebd224d13cc43f8fff12f38091c2b3f2102d5c20d8b1c3ae4f129364bbe9f9ce2147dcf0639668ddb90dffe6a50f939f53fa7ba358e913f",
	));

	test32(TestCase(
		/* nonce */"98013e248c44840860e7319a",
		/* key */"bc17e037902e1e9baa9d6715ee234af9fe6da80d4ca8eec3999719dd92fbef6e",
		/* input */"7024974ebf3f66e25631c0699bcc057be0af06bc60d81a7131acaa620a998e15f385c4eaf51ff1e0a81ae5c6a7442d28a3cdc8aeb9701055e75d39ecac35f1e0ac9f9affb6f9197c0066bf39338a2286316e9d1bb7464398e411da1507c470d64f88d11d86d09e6958fa856583ace697f4ee4edc82618662cb3c5380cb4ce7f01c770aab3467d6367c409a83e447c36768a92fc78f9cbe5698c11e",
		/* output */"ff56a3a6e3867588c753260b320c301ce80de8c406545fdd69025abc21ce7430cba6b4f4a08ad3d95dc09be50e67beeff20d1983a98b9cb544b91165f9a0a5b803a66c4e21bd3a10b463b7c1f565e66064f7019362290c77238d72b0ea1e264c0939d76799843439b9f09e220982eb1dc075d449412f838709428a6b8975db25163c58f40bf320514abf7a685150d37a98bac8b34ccb5245edb551",
	));

	test32(TestCase(
		/* nonce */"6d864ed2d8259dc5f123f6fc",
		/* key */"a0cc325fc5ca6741ee4349c0eca17f50c0df8fad2dfa66624153f0223e147480",
		/* input */"8d79329cf647e966fde65a57fc959223c745801c55312046b791671773cca0af4cd48ead1f316eba0da44aa5d18025eced0c9ed97abaabb24570d89b5b00c179dca15dbae89c0b12bb9e67028e3ae4d6065041b76e508706bec36517a135554d8e6ef7cf3b613cbf894bec65d4dc4e8cb5ca8734ad397238e1e5f528fa11181a57dc71cc3d8c29f3aba45f746b1e8c7faace119c9ba23a05fffd9022c6c85260",
		/* output */"60aea840869f7be6fcc5584b87f43d7ba91ed2d246a8f0a58e82c5153772a9561bdf08e31a0a974f8a057b04a238feb014403cd5ffe9cf231db292199198271f9793c9202387f0835a1e1dc24f85dd86cb34608923783fd38226244a2dd745071b27d49cbffebea80d9dacad1578c09852406aa15250de58d6d09cf50c3fcfff3313fac92c8dad5cb0a61ccc02c91cecee3f628e30c666698edecf81831e55ec",
	));

	test32(TestCase(
		/* nonce */"4710b63001f90c812415684d",
		/* key */"d07614e58d0098df9ee6df596691b30d4a4a1e6c5e1676fb85f1805135fb5973",
		/* input */"85484293a843d2d80b72924b7972dfa97cbe5b8c6bcc096f4d5b38956eb3f13f47b02b0f759ea37014ecdecfb55f2707ef6d7e81fd4973c92b0043eac160aaf90a4f32b83067b708a08b48db7c5900d87e4f2f62b932cf0981de72b4feea50a5eb00e39429c374698cbe5b86cf3e1fc313a6156a1559f73c5bac146ceaaaf3ccf81917c3fdd0b639d57cf19ab5bc98295fff3c779242f8be486ba348bd757ba920ca6579be2156",
		/* output */"bb1650260ef2e86d96d39170f355411b6561082dcc763df0e018fdea8f10e9dc48489fb7a075f7f84260aecc10abcfadbc6e1cd26924b25dedb1cc887ada49bb4e3e02006bdd39098ef404c1c320fb3b294ded3e82b3920c8798727badfb0d63853138c29cf1ebf1759423a1457b3d2c252acf0d1cde8165f01c0b2266297e688ff03756d1b06cb79a2cc3ba649d161b8d9ef1f8fb792bd823c4eabb7fb799393f4106ab324d98",
	));

	test32(TestCase(
		/* nonce */"be0c024290af62adcd539e02",
		/* key */"9520adab77c41e60a123c93b1adede1e5523613358485b281467fdd3c3bcf4e0",
		/* input */"a2fc6e1b5281a4e0330eecd1ab4c41670570423173255979953142b78733b2910fa5540e8294208df6ae4f18672d5ac65acf851bcd394e1932db13c81b21e6f165e5538aff862e46126c650bbe055e54b31c78f2f0221d2631d66ef6d3f4c5ae25eada043b74d8770e2c29799c0954d8ccbd17766b79e6e94e88f478db3566a20cb890846917591a07738328d5c05f7ed4695a82607660f1239661faa9af0368aeb89726f13c2aaecf0deaf7",
		/* output */"d8fe402a641c388522842385de98be60f87d922c318215947d4b7562d4ca1e2dbc7ee86494e65fb0bfddfdebdb2ae6469312f95b32c722b2720d64bb8d7cc3dd82f9055b1d89f05b77984f91f94ba4ac79c5129cd7c91cc751b0defc3f2799518e372d27aa683f1e7bbd4f55414c48fe8a3a37ac1f179a1a329cda775aec0d31d75a5a38addb1de67c06bddbedf4c8d87abc18c9f9dd072d457ea29ad4dfb109ce7e99a4a82fbe330b0afbb5",
	));

	test32(TestCase(
		/* nonce */"8f1c02a8c4027a6693b6687a",
		/* key */"c801e4ec475a80faca2f576d0c781c9ce5457564114cefd7461edc914e692aba",
		/* input */"480387bc6d2bbc9e4ced2448d9ec39a4f27abe8cfb46752d773552ad7808a794058962b49e005fef4e403e6a391d1d3f59025eeb5fb8fbbe920f5361862c205d430eac613cd66108f2f2f0bd4d95a8f6ca7bd1f917eaeb388be87d8b7084a2eb98c575034578edf1b3dafff051a59313873a7be78908599e7e1c442d883d3fd3d26787eb7467eed3a3fb2d40046a4460d5d14215565606bcf8b6270af8500e3504d6d27dacf45bace32214472d525fdc",
		/* output */"ab81a9c28358dfe12e35a21e96f5f4190afb59214f3cf310c092ab273c63cd73a783d080c7d4db2faccd70d1180b954cd700c0a56b086691e2c2cd735c88e765e2266cd9ebe1830d63df4b34e2611a8abeeca9c8c4fac71135dafb1cb3569540ed1362ddeb744ed62f6fd21de87b836ec2980f165c02506e0c316ae3cf3d18a862954d9781f726ecc1723af4a730ccc6d6de82553450a52499acb58fb2008969401c45b2f20e12b58f308db1d199b4ff",
	));

	test32(TestCase(
		/* nonce */"7c684e41c269fcc6d312cad3",
		/* key */"ca1cb501af5584bc4248903f52b4426064d14dcdf0f383da72b904ff0edd72f9",
		/* input */"b274e61059f3215173ae226e30a92ee4b4f8a3da95f2e768e3fac2e54ddac92c200c525f190403a6ef9d13c0661c6a7e52ed14c73b821c9680f1f29711f28a6f3163cf762742ed9474dbea51ff94503a5a404adbbdfbf4c6041e57cb14ea90945dc6cb095a52a1c57c69c5f62ac1a91cd8784b925666335bbfee331820b5f7470bc566f8bbb303366aafe75d77c4df5de2649ed55b2e5e514c3cb9f632b567594a0cf02ec6089a950dbe00554ee4dfb9",
		/* output */"a0969730d48ee881792a3927b2f5d279aba9f2ed01e6b31b92d0e1fb8ba7f35a236d838e0ce5f8654957167de864f324c870864b4e7450a6050cd4950aa35e5a1a34a595e88dd6f6396300aff285de369691b6e0e894106dc5b31525e4539c1e56df3ceedbbab1e85da8c0914e816270a4bae3af294b04a3ea6e9ef7e2aab4da5f5370df2706b5e3f000d88179ac756deaa652a1cc85e80ad9622f1bf91a2776262eb7289846d44f7f8192e763cb37aa",
	));

	test32(TestCase(
		/* nonce */"1d5c31dd98da35230fdaa0e0",
		/* key */"d6c71964420f340db8f4f27a42cf3635fbc6682f5f859dac90d4c407b1b11197",
		/* input */"ee849039c6cd972dc943d2a4468844d130c0150276f4e0889047e2300c3ecc6792c4527bfe9437dad877eb986e6b1aa9b867d1798c9d314243f0a87ec9ee5b601c2554876c87cbf50df3334a077c4152f8b8fef4a2d301ddbfa90c887ece757c3eb6c4fc1e0212d6b5a8bb038acaec28cba064c9b34f5364cb7f0fc2ac4ef2c7ddde0f5ba17014459eaa78f08a46a01882ebf7c6e409dadda250bb899dc8b3b70e160bbcb4412a9963b174d0fc6bc16383a46ffaacb6e0",
		/* output */"3e272ded9c0a5cebe7cf17ac03f69eb20f62996e047501b6cc3c8691ddb2780ea72c21a81888bfea96e4373a412c55ca95648390de740102d661143043baec3976230e024477d134b8504a223c36a215b34164c9e9e1fa99a49fdc56f2f04ea525a6b82997d9bbc95c4b5baeab4dec50061efb7c1a757887acb8b47b142e0a2e61885a2c14c4642d83d718a0546b90699adc545a48129603862a1c89d8e665cde54b3ba487754db6d6f5acf6a4b95693cc569577a2dc48",
	));

	test32(TestCase(
		/* nonce */"7c4fb4ebddc714af7acd4345",
		/* key */"7719e70c860e7999dcd61065e78a96379afb17295ff29e0185d082d243d02861",
		/* input */"0992396a6f29b861dd0bc256e1d1b7dce88435733506a6aa20c62e43afa542d1c46e28b2e6d8e2eacb7c08db05e356fe404684b0e3a9849596db82eb788aa09258c28eb19e9838f757425b4edef12deeca56e30cf030272e325d4246d6e083219b2f965124963ca91f066d47bf5a8282a011a78b0155aa70038259a4a59135f241fd2f88c908b9f4eef7b7df0f3a1c16a52c009b522f89dabd52601bbf6e3ce68732e1a6d444469480f06da218786cf6c9666362e7a7f7be12",
		/* output */"545c05a84b5a4fffd1dd623c8f2b11443818560bdb0c26dadd3b694d4790d294b99059f4127b7cca122c4000954d745af96094ff4623f60db33e994bb6903263d775f48d7047427b3a498c2ecde65bd37bcb8ee7e240a1e08c884c0079cab518f4e1c38ba5ea547f4da83b7c6036e4259bee91c42e8fae895df07781cc166f1d50e1550a88ee0244bb2950070714dd80a891aa8a9f0580a67a35cb44609b82a5cc7235f16deea2c4f3667f2c2b33e8eeef944e1abdc25e48fa",
	));

	test32(TestCase(
		/* nonce */"9071cb35869a2e21e43c42bc",
		/* key */"dece19faf2e86a57ab5d05585d35b3911a50d269c223637385136c2657454f13",
		/* input */"3b9efcbbb607fad5e9f1263dad014cc5c2617d439fcd980408f4f9a93acb1a33d1c3a22f38c037e4603dfbbfb5571bc08c4a1958cbbf510e3e4dd19007fe15fad7808369149a9c4db7ca0496f7a600a6f2454ee1cffd5a68d45c270e4b53ac9b77f33a1ffbb1804244f57d2b05b8036fe2cda9efead3d4eff074ea5c07128e0b354a4a11ffa179163933bc6bd10d200804cc93b64575746e94e975f990bddcc8a4335e99e2459fbe9bc0e004ffcd6cac52f48ef55cc0637a75c1dc",
		/* output */"631ba7301e33236da2477506ea98d3b732447389e849b68e1f09bd5fd814f40dc3247a1012fa654f08e3dda0c104ee2dff12ecf5cb018644de50d70dfb6c8cc1f5f552e5f1e50466bbb538ad6b98fd37f33fe615c326efc9cc97899b829b007f91569fa9b28ce0076c53daedf9cc0f838e22cf1125b86a6a2c2eb4a45dadea45ad00fb4f054e7d6b09c13ab1dd5328debfbf4f1b70af2b8a5b1d02df8a87d7661473e0c180ba4c815f14db87c5bdc15f11a29d8e0ce3d747d5dcd4",
	));

	test32(TestCase(
		/* nonce */"ac41c9cc025ba4dbd67a0dab",
		/* key */"5207759b0a0927a6f0957c963f2cfff87eb9be69c1990ba383dcdd0aaf9b3f44",
		/* input */"f28a71efd95e963e5e0bc0fcf04d8768ce93cb55dc73c32e6496022e214596314b7f843f5c7b136a371c2776a0bfbdd534dccbe7f55e9d3d3b5e938f2d7e74393e4caf6c38fa4b05c948e31dc6a9126817fa3d7892c478f75ab9f6ab85c0e12091bd06e89c7d3ca8d9dcdd4c21fead3d769a253919c2c72dd068474ea322b7e71cafa31684e05a63e179e6432fb70661792cc626a5060cec9e506b35d9286f15dc53cc220b1826314eec337dd8e7af688e5950b2316c30516620569ea65aab",
		/* output */"1bcea54b1bf4e6e17f87e0d16388abe49b988b9c785b31f67f49f2ca4011ecd2ad5283d52ef707dd3b803e73a17663b5bfa9027710e045a0da4237f77a725cf92792b178575456de731b2971718937dd0e9ea12558c3fa06e80bbf769e9799f7470db5b91476d6175f1a6d8e974fd505854c1230b252bb892a318e6d0c24dcc9ecb4861769cd746abab58805bc41c6086a6d22b951fba57b00c5b78f6dcb2831715b9d4d788b11c06086f1d6e6279cd130bc752218d7836abc77d255a9e7a1",
	));

	test32(TestCase(
		/* nonce */"587c7e98949a83cc602e9530",
		/* key */"6f284ae396d9dc4a12871697e8dd820ae54942010b81825ee845a4b4b0ad7995",
		/* input */"c1d1ede73bd89b7c3d4ea43b7d49c065a99f789c57452670d1f92f04f2e26f4f5325c825f545016c854f2db2b3448f3dc00afe37c547d0740223515de57fd7a0861b00acfb39931dc9b1681035d69702183e4b9c6559fb8196acbf80b45e8cc5348b638c6d12cea11f6ef3cc370073c5467d0e077d2fb75e6bf89cea9e93e5cf9612862219ca743ef1696783140d833cd2147d8821a33310e3a49360cb26e393b3fee6dba08fcda38d1b7e2310ec1f715e3d8fa0c6b5e291eea07c25afd5c82759a834a89cc5",
		/* output */"11a8493cdc495c179f0d29c2b4672997205a9080f596ee3c80d79b55162b1c875ac18eb94bf2a9e05b08024f524a1e9665912394a330c593d23260e6bdf87620c10a48f678693196fb744c49054182fba667c601e7b7ebf0f068e8d69ba004b804fda616a4a0d5350e1a3bd424b8266462be282308219c578569aefc1ccd09ecdf5da283356c9e524e14e69d25b0e19643dab26f54373a7272b43755c3f1ddaee6c5fb9e8e093110c41697e95f73a68c75454e050239197c9fbd8cec76698bd11894ebf6e2b2",
	));

	test32(TestCase(
		/* nonce */"5a021f8500c8f3e63075ae85",
		/* key */"47be0d2d65e405dab2b3f6429ee726708066449e76f91d69a23db2f7fa2134bb",
		/* input */"37b2dc4b6a5203d3a753d2aeffcdaed5a7c1741ed04d755dd6325902128f63b6981f93c8cc540f678987f0ddb13aae6965abb975a565f0769528e2bc8c6c19d66b8934f2a39f1234f5a5e16f8f0e47789cd3042ca24d7e1d4ddb9f69d6a96e4fd648673a3a7e988a0730229512382caaded327b6bbbbd00a35df681aca21b186bc7ac3356d50889bbf891839a22bb85db4c00bfa43717b26699c485892eb5e16d1034b08d3afa61f3b5f798af502bba33d7281f2f1942b18fb733ca983244e57963615a43b64184f00a5e220",
		/* output */"b68c7a2a1c8d8c8a03fc33495199c432726b9a1500bc5b0f8034ce32c3e3a78c42c1078e087665bd93c72a41df6bfa4e5beb63e3d3226aeeba686128229a584fab0c8c074a65cef417ad06ab1565675a41cf06bb0fb38f51204eccccb75edd724cdd16b1d65a272f939c01508f0385ca55ac68a0e145806317cc12e6848b1124943a6b2d99a8c92083fc5f31ab2e7354db3f8f2d783dbf1cfec9c54f8bfcb93d6f28ef66f18f19b0fab8836458e9b09bee742ba936cb2b747dd9dcf97ca7f6c82bf0af6f1b433592d65143fe",
	));

	test32(TestCase(
		/* nonce */"7fd9bfae2d4483f51f2fab15",
		/* key */"9bcfd1d3e68731e457a77150b4832a416f71273f88c4fd17ed771f2756b04b6c",
		/* input */"68c2c5612912b5f994172720130dff092ee85a2c1395111efa64d5a281ca864d3db9600e685854d81c6de7e8747b92fb7c4c2efa829d3d4c0c9fc9d689e2e5c84c9eae8ba4ab536fb6c7523124b9e9f2997f0b36e05fb16163d6952eee066dd22fb7585925ffded0204cc76818bcead0d1f8095ca2cf9cd1ddcd0361b9c9451940e14332dac4e870e8b2af57f8c55996447e2a8c9d548255fe3ed6c08aedaf05bb599743ecb0df8655152bbb162a52e3f21bea51cb8bf29f6df8525eb1aa9f2dd73cd3d99f4cca31f90c05316a146aab2b5b",
		/* output */"d0ae327fa3c4d6270a2750b1125145bdeef8ab5d0a11662c25372e56f368c82c6f5fc99115a06a5968f22ffe1e4c3034c231614dd6304e6853090c5940b4d1f7905ef4588356d16d903199186167fec57e3d5ce72c900fe1330a389200ed61eec0bdc3672554f1588ec342961bf4be874139b95df66431178d1d10b178e11fcbd26963ff589d5d5faf301b7774a56bbfa836112a6ea9c3026ebdd051085f9131132c2700674bef6e6c2c5b96aace94eb2ba6c0e0aef0eefa88995e742ca51ac50af83683b801b7c2c5af4880e2b344cc5564",
	));

	test32(TestCase(
		/* nonce */"b873e9f9a7a68524e6dea72e",
		/* key */"11efed96267ff58c3ca8e3b6c634f49e48ea07464d7ee8ac7574d8a058949c3a",
		/* input */"fed3d1efa309c8b50cb9da02b95167f3b77c76e0f213490a404f049270a9c105158160357b7922e6be78bc014053360534add61c2052265d9d1985022af6c2327cf2d565e9cef25a13202577948c01edc22337dc4c45defe6adbfb36385b2766e4fa7e9059b23754b1bad52e42fce76c87782918c5911f57a9394a565620d4b2d46716aa6b2ba73e9c4001298c77bfdca6e9f7df8c20807fa71278bd11d6c318ed323584978ad345c9d383b9186db3bd9cec6d128f43ff89998f315dd07fa56e2230c89d803c1c000a1b749107a3159a54398dac37487d9a",
		/* output */"6a95fba06be8147a269599bccda0ce8f5c693398a83738512e972808ec2f25bc72402d4bcd1bc808cc7772b6e863b0e49d1d70c58fcf4fcaa442215eeb3a4648ade085177b4e7a0b0e2198f0acf5465c97bd63f93781db3f0b9a0a184c3e06a76c4793a13923f83b2242b62511c2edff00b5304584cbe317c538de23785d2504fae8faabee81c5315298186ce3dcbf63370d1ccd9efec718cbc90b3d2e0b0b6aefb3a9b31e4311f8f518be22fdc2b0f00e79a283701c53f6936dd63734ecb24480d5365d1a81392498faf9a1ddee577007acc5f8c87895be",
	));

	test32(TestCase(
		/* nonce */"444cbde3315ab7a30f0192fe",
		/* key */"8bab05ddd17cac05203711b806475253a1ee0c8ee723eb520b73851cd51439b3",
		/* input */"d776bee5625d29a2ebf6fec4df94d2b9ac62e8e7c56704fd38a87ee932b787cbc555621535e76ea30183cb0ee30604f485b541f45feb8c01b9750d37fded5cdffbbc34fb90fdc9c7c7ddf949a1d50b796f1ea5db437238c7fb83c4b22c9e491f75b33d84746f1cd10bfda56851b8514ff0ded0adfd5092a66a85202d06bd967485d06a2c56011110da74bf40b6e59f61b0273164744da02ce2b285d5c3f03aee79eea4d4503e517177692ed3bb035071d77fc1b95c97a4d6cc0d41462ae4a357edf478d457c4805fa586515614697e647e19271091d5734d90",
		/* output */"60e9b2dd15da511770162345251edfb15cea929fb79285a42f6c616dfde6befc77f252e653b2d7902a403032fc4ce4934620931a2ec952a8d0f14bf1c0b65cc287b23c2300999ed993446eb416749bf0c9c7dfe60181903e5d78a92d85e7a46b5e1f824c6004d851810b0875ec7b4083e7d861aabdd251b255b3f1fd1ee64619a17d97fde45c5704ab1ef28242d607d9501709a3ac28ee7d91a3aac00cd7f27eb9e7feaf7279962b9d3468bb4367e8e725ecf168a2e1af0b0dc5ca3f5a205b8a7a2aae6534edd224efa2cf1a9cd113b372577decaaf83c1afd",
	));

	test32(TestCase(
		/* nonce */"50fdabcd995b0dd1850a169e",
		/* key */"e9a431828b3cf3891bb1960f9dae3c85334a62f6ee2395ee5378bb28f8c68a68",
		/* input */"4f57848ff5398e61bcafd4d4609bcd616ef109c0f5aa826c84f0e5055d475c6a3a90f978a38d0bd773df153179465ab6402b2c03a4bf43de1f7516eb8626d057ae1ab455316dd87f7636b15762a9e46a332645648b707b139e609b377165207bb501b8bccfa05f1bf0084631c648279afdf51c26798899777812de520f6a6f0d3c7f3ef866982f5d57f9c8d81c9a4eabb036651e8055a43c23a7f558b893dd66d8534bf8d179d8aa7d9e8987cfdaaa7b5a9381ba9c79d5c1161b1bdbd30defdd304ee07f19b7ba829a0d5b40a04b42edd6407b68399caac69069",
		/* output */"e096cc68956ed16d2dea1154a259e01647913eeea488be0b54bd1816c781a35e161772ae1f7a26b82e864ade297a51cc9be518641b2e5f195b557ec6fc183e4e5c1fc01d84fe6ca75e5b073af8339427569b1b8ee7fcff0ffa5e7e6237987c40deec0abf091c06a3b28469c8f955fc72e4f3727557f78e8606123e0639dff782e954d55e236448f4223ff6301accda9f8fa6cd43a8d6381e5dde61851a5aec0f23aeca7262659bc793ce71fa7992f80e44611ae080b7d36066e5c75c30851306f0af514591d4d5034ecdf0d6c704bfdf85473f86141c9eb59377",
	));

	test32(TestCase(
		/* nonce */"3f32de67c92a44a0d9b1779d",
		/* key */"d4338dcad949438381d5685e0ec3a79938607fdc638b7e69ce2e4c28fa3b3eee",
		/* input */"046a61c0f09dcbf3e3af52fab8bbcded365092fad817b66ed8ca6603b649780ed812af0150adbc8b988c43a6ada564a70df677661aff7b9f380d62977d8180d2506c63637c0585dcef6fe3f7a2cf3bbb7b3d0df7769f04bf0f2e3af9439ab7615c304b32055aea0fc060890beb34fa9f90084814b6ed7363b400dfc52ee87925c5b4a14a98e3b50c7f65adc48c89ddd6414626c5e0bdefabab85c4a0e012243e682d4931be413af62fd7123ab7e7774fcae7e423bf1d3a31d036195437e9ea8f38aa40182daa9aacf3c9f3d90cc0050977c6065c9a46bcca6ba745",
		/* output */"cd5a6a263e3ee50dda0e34c614b94c3ec1b14b99a2f4095a6b5715fdfc3449fcdf8a09d1ae02d4c52e5e638f1ee87a4a629f99f15a23dd06718792f24285f5a415e40f698752c697ee81f2f9248da1506ce04a7f489f8e2b02e6834671a2da79acc1cdfb78ea01822d09a1c4a87ffa44e56c4f85f97507044cf946ccb6a2e06e2917bac013f608d75ee78fa422a5efc9c569226bf7068d4705fde3a9fad2030256db0acf9a1d12666e0acf9f5346ad62e5af4c01a008d67ab1224b3e98278d073116ff966cdc779fb3aff985ec9411a3eefa042d71dd4ae5b15d5e",
	));

	test32(TestCase(
		/* nonce */"5a3d6aa35fa04717b40e4405",
		/* key */"e61e702d1a5a3d14abb967bbcc8cc8ab8fadba208be40765391b1edb801d529e",
		/* input */"af516216f74a6344cbe458cbba820f7e25c0b10aa84b790da2ee6317e059171076d7246c2878be83fc00c200d546c007f849e4c163d52c7b0da31beff4abff481be3266b92e668cf4dd1c84d9d7b3e5191dcd6ddb51d17d337621046e83e9ac035fccfb239648bc3c6fd340fbb50707e5a33b3ef439d292192d0e4bc727690c61450e5a28789e5ea50e746bc66d039493e080fb70e9ae06d89004cb71de8178941c422f1e9862492fc9149a4864ff52b1277b9f5a63c2f16e9adb5263cf65a034a62ebb0f1a385d2681c87a35f1c45670b4edef1c68fe9544fcf411d95",
		/* output */"b22ffd8f0e549bd3e0206d7f01ff222f92d39b41cf995a331d5ef0cf5c24bcc3ddb36e64d351b5755400246fe4989b5f912e18daa46cdd33e52dafbd2872f16e94220b56315d72c1dbb1525fd34831d7202970c11711ff36de3fc479407c34fef0aea86e172f9beb0f393194355b9dd59625639f4a6bf72ba571c229f2fb053c1114e82793deb2dfe8232f1a327949689d2fb2820662dcd2a39a2546c7df12b3ff7e87e58c74badf568cddebd3c558f0f7874c834c4b8aa988653f138ec79620f5e3ed737690928a30f981dca9f2920ac7307607063b40f87c204de47c",
	));

	test32(TestCase(
		/* nonce */"22e02bb9c757121e1ec0d70a",
		/* key */"9cbb1dca0495dbaa5ca9b8775eeb0dc5b80fbc2dc24b659e5a92d89466fb9cfe",
		/* input */"a3d70bdb509f10bb28a8caab96db61652467cf4d8e608ee365699d6148d4e84d5d93bdabe29aa4f0bc8ee155f0b1fb73293c5293929eaacdd070e770c7cccfb2de120b0c3811abeeddaf77b7214a375ca67d618a5d169bb274a477421d71a651cfb9370bcf7e0d38f913754c11002089cf6cd6a8de1c8a937fb216591d57b37efdf3797f280773950f7eddeb9c3385c8315ff5ff581c64610a86ada7ff6a1657e262df94892dff9fdfb6e958d101f4c26296470c138dc4e1ca4bb565b3ff877a7f78b3d11d64b7c24e27ba6f6b06f6e368f5ac218cd5d11b815ab0987678eb",
		/* output */"646314264896a6e25601e536f6e783d465b2ead1e0be4422bc9cc8eacabae4a749ad533eb28091be8397328dcfb34c92006bbda930ab070ed7b806095bb1c8f476350e7b08ffbd4d7d6055c8defaa8deff9d54f5215c2d7db27ce09e08f5d87a859145ea3126e2a01882921c3fddef3985bd451bca44063258390aec8ec725b07d064314fe43a9c83e9287b47616dfefbf539b82da209aa08a6d3176b7e3b4be4a17d44e581280a684e4a64414649bfcea82b541729f8178b580e8b972a89f5b8c4f9b68205e9396d8ae5e81873b61da074080fd44c52d50fb0880ee9c35da",
	));

	test32(TestCase(
		/* nonce */"27190905ba751c66ad3dc200",
		/* key */"9d49002edb63dcaffb2ec6c3197a15b4138bce84796232859d1ee72ee4218731",
		/* input */"f48b5ae62f9968baa9ba0754276cd8e9dcfa8a88e4571856d483ee857b1e7bc98b4732e81f1b4421a3bf05ab9020d56c573474b2a2ac4a2daf0a7e0c3a692a097e746d12507ba6c47bec1d91d4c7cfc8993c6700c65a0e5f11b1ccd07a04eac41f59b15b085c1e2a38b7d3be9eb7d08984782753ae23acdafbd01ae0065ab9c6d2a2d157c1fc9c49c2444f2e5f9b0f0bbfb055cc04e29b2658b85d414b448a5b62d32af9a1e115d3d396387d4bb97ba656a9202f868b32353cc05f15ae46cbe983d47b78ba73d2578a94d149e2c64a48d0c1a04fc68baf34c24b641ea0b7a800",
		/* output */"b9af1016275eaff9905356292944168c3fe5fdffd9e4494eb33d539b34546680936c664420769204e91ead32c2bb33a8b4868b563174d1a46108b9dfe6d9ac6cc1e975f9662c8473b14950cbc9bc2c08de19d5d0653bb460bea37b4c20a9ab118a9550bfeb1b4892a3ff774e8efe3656adcdf48239f96e844d242525ee9f9559f6a469e920dcb3eaa283a0f31f5dfac3c4fac7befa586ac31bd17f8406f5c4379ba8c3e03a6992a1915afa526d5ed8cc7d5a2605423ece9f4a44f0c41d6dc35a5d2085916ca8cabd85ac257421eb78d73451f69aaedeb4ec57840231436654ce",
	));

	test32(TestCase(
		/* nonce */"7c996d5d8739629d36de4257",
		/* key */"eaa5b2578bd6bdc5c6b0c79960a9ae26f1755cba6bcf04a9de315068990e0f0a",
		/* input */"b39101601efa2ecdf41878b0fd920a3005ce709e4ec2970abb76e32c232ea21069f81b246eda75aace7555ce8ae203455d3723e684bd671389300e353eec0d2f499d10654fafda2e7a69bfca7198eb172249167ca8864b5d5f58d28723090ec86e251a1bac0346d52fd81f06e0c05429e0b2b895588290b7d00878a4da3378eb6c7e61487de2b318fedf68fa7ad7c88ee746827c1f60d98c7716f3f9695c5ffd4670f71a0fa78a1fb554ba482c5de83feaed7c65fc71acc9f541342eb8f7622b12bb2cfa222fa2ddd8b3ed210ce442275afa3132c8a0e17dd504ecbc92525c118952be",
		/* output */"50eb5b21c179a03b9a822f0075906a3ce4acc32486139f92635c7d834f69071d5a6dc0e15ed06a5cee37147071d59641d140a82ad5815b954e7f28e080c3dbbeaf13943d7b7c66d49d51ba1132eeadd4cb7a7e7d726d08d95f1578d55519f267f753f3e16ff39504a87b2286d8bfba0fe6bc28887b466bf276453a82cdd0abbbbf08db0e1c26c317d50ad9b8dc09cd621bc566d362024e8404739df6468869d2125c58b25d70e392f5e75924c4341be81c263915bb514ad436fb24c2c67450e84f6d1b72d1a02a3310c07a7814d930264fdbbf5ddca7067e18e8a44faa87169b7f2e35",
	));

	test32(TestCase(
		/* nonce */"07a7bc75f4d1f6897a656f2a",
		/* key */"cc429f94483c5d2b73e40bfeaa92ac17ddd9c9bd26dff97408754826a2417b7c",
		/* input */"0a42f63b975ad0e12a1e32615813dfd6f79e53ce011e2a2f0534dd054689f8df73a8326fecfd517ff7fe530d78081af66c3a8c7c189eb9d9efed1e5577b5512d42ef1fe273f670ce380c64bc62e217a7e410a8ed89998344e29301e4e053a3a3cf7e71587fd056a6bd976f16e157476a06997dfaaff32172dd84190570621f2221420c0a0ea607ea756e9792c8c0e7157c95b89c9490e20b750ee85e4c27c9b8f409e848ec90afcad33342010bb9808358afbcb3d9b094127c38c243a204e76899677079758e7cbada9a5c18363449eebc07bab516a16372722403a046df85c7dd2ffc804c54d38aab",
		/* output */"87a47bcaa1c1eb8e55151011c4f39af4b9e108a55a7124cdcf66d0dee727306e6971f783b038bd6b215f530cdbb53e17975742ec304fdb3792a88b674504396978c6a5e4a9c87a7c3ca430d61165c1a3f6162eeaf38c93e18b6ccb6a595ad428cdc98efef8f84463eed757a72ffd827b71c0579fcc1f4baa11812be2bc5a2a95df8e41d04b33343df09ce628c367d1f88488f7a2787f013c8e76f0b9257cee777ec4adc6df8c5790e41ea02da85142b777a0d4e7c7157a48118046935f8888b5352d1750bf00b92843027a349cf5685e8a2a2efde16dcf5e1c1ed8c779bb38cabfb42ec4dd87d58273",
	));

	test32(TestCase(
		/* nonce */"f7a40350de8cbd4025fb35fe",
		/* key */"d9496e57dfe9840ea327f209e09d7c43dec86ac42b2d6a1a8476ab42b6fb5342",
		/* input */"abeff48fa082dfe78cac33636c421991b0d94c3bc9e5bd6d22763601a55201fa47b09ce60cb959ba107020213c28ae31d54923d1e74ab1d9ddc2762b2d23d8c6961d81068230884a39682fa4b30676ffec19319362c075df0b879a0f083a67b23597bf95c4bb997fae4736479cb8a9c00520ba2f6e5962d54c313c576180d17779ff239ad60f1f1373627770d50a1c49718b2b2e536846299e052f8c1a5d3079e91cb1b8eac4661daac32d73b3b99e2051f8f694a61d1e9d3935f802921a4d979b6ade453cf30d73a4a498a6a2c5395c60fcf271d50b4967ac12b0d7bf818c2679d552e9b3b963f9f789",
		/* output */"a0d11e732984ad575570ed51031b8ac2d7b4c536f7e85f6fce9ef5d2b946cefe2ee009227d6747c7d133ba69609f4a1e2253d0eb59d1f930611e0c26a7c0cf2d2ce7ccea6e079eadf2eb1acf0463d90fb4b3269faae3febfc88cb9fb0873d8b74894506199394c8e44a96e6b479bd3e045749cce1c3f57243abdb37e67084eb573cd820c6cee424227019592a027e9da8f7b8997bfb292627a986f83c8fb8d156a91a12a8b52659cf9272924631745ed3a2453a4c2d87a167faa9104e799c715ed597bcb66949ab15dae29a86ba147507e8d8af66e96c09c53caa053ad3b79d9ed3c0c6c00169eaec3a3",
	));

	test32(TestCase(
		/* nonce */"ce48aec66f90f026bfb88afd",
		/* key */"502cb8420d9e517f9850b9cb32e5756f1bf6c9e242f94a5a7b7779269c1c8e6a",
		/* input */"a77b7a5870335b9145fd2e08ec898ba2f158fda16e8a2661a7a416857b6ba6937b4843ecaa79d3635d28383af80290842de9ca0bb621ee22b7fd6bf379922741e812b1739c33dd6923d0607826fc84d46bbdbd1fe9d1255f56a167779a560a6eed1b9c9579b8f771147df467e67a070d9e9ce8ad92dc0543d1c28216c1dec82614ac5e853ed49b6abac7eb3426ef0c749febce2ca4e589d06ccfc8f9f622ede388282d69ceb2fd5122ba024b7a194da9dffc7acb481eabfcd127e9b854be1da727483452a83d1ca14238a496db89958afd7140dd057773ea9a1eee412875b552d464ba0fab31239c752d7dd3d9",
		/* output */"b330c33a511d9809436ab0c4b84253eeda63b095d5e8dc74803de5f070444a0256d21d6c1cf82054a231b43648c3547aa37919b32cfd9893e265b55545be6d7cd11d3f238ef66c3c278fcccb7dd0dc59f57750562cb28da05d86ee30265ff6a3991a466ba7e6208c56fc8862e19ac332e5fb3cbcc84e83a6205dee61a71acd363a3c9de96d54070a69860c152d4ceb9c4b4cc3b878547b6116699885654b11f888dc3c23483a4b24fbe27c52545c06dd80ab7223d4578ab89bff5f9cbf5d55b19611a5251031df5da5060a1f198226c638ab5e8ec5db459e9cd8210f64b2521a2329d79228cc484c5065ef8a1d",
	));

	test32(TestCase(
		/* nonce */"8b6738eadaea410c7b148133",
		/* key */"acc28f26867e2921cff89edf3452b4d4f2c4952ae36cc3cec938fad59037c47d",
		/* input */"322d634bc180458123e10d0509870b54e0f0a3a72a2bd9e9cf44324c7a1ca37dd6adf9db1fcc8dadabd881f91d47d93b58382802b42ee936802fac8612ea4dd9eca5f215935ea9ba6233b9c8bddba3385861de669d95c888c8977851cb305db577a4eb2360f362fa459d61ffc8fcaa1502905b073bd8e9567ac7cff8e5fb1002c55641a3af5fc47ac0131fae372f073e19721ffcce9821e0241d7fa67bfc499c8f100e050d39bd4d7cae4557d208629603ec4a007852762ec1905d0e81b873510fd334dedcd9c288eb8415db505913af06bea94d197ab627d58f6a9944f6c56247595fc54ae3f8604aa37c3466f74561131e11dc",
		/* output */"edbfb1090987762f75eba2439d746cdbefe8605b8ebad59e075d28b54edfe48813ccae891f6ed655c5ab5211ba896fff0c8e09bd1554aad987dc53f355d0822e9b0f524a99a79c68a9f3b4e30506cd725b07be135e4540078be88dac64fc545c433837b96a924452f6b844291c4c3fb5f8cc94f06d9f19dad7fc945f093020e82ed19f9eb3ddff68b813629991d1a460e5455e1cb41cf23bb3d96fdb6b96581c3bf9ef72814406329bbbba5b835e7724c728cebe88efcd996dea71d0fd5c53e081c21ce8b3764738d693e390fbf8e0137a716760fc9cd2014cd9bf3fd706bc3464d1f15803606976e96b1077cda0a62921ff7c32",
	));

	test32(TestCase(
		/* nonce */"84c53a88d5e7b88f66de07df",
		/* key */"477e74c7c6883d8531a69abf8064f1788080247c3b97ff15408a5231e5869662",
		/* input */"e6b8a9012cdfd2041ab2b65b4e4f1442794fdf1c3685e6622ce70f80b9c2252ba6d9e6384d474a7622053d35df946a3b19408b3e1712da00525070279ce381359b542a9ad7c07750e393e0834593777352c1f7dbc84cc1a2b1eba787377d2cb1d08a7d20e1393d44022107acac5d765be37f9075af02e4bbf8e60ceb262aa34e2b870cc7adcf54329a667249cb4958393bff4f4333338cae45cbca419d59e605aa0cecb1241080339198b9b283e4201afc07360b8ae2a57b0b9b97167c315f03fd7a87a00ae73f91ca560a1505f3cdf04576b9aee5ea775f719916f1e1942ad5311c7f87153f8e62855ace3f34afb08d4d7c7f4fd2bf83e42f76",
		/* output */"fc2673c80812d101bca7a2e0e105fa449550e695a016596f5c3cde11fb7dc518b94fdb74058e634546a726c37896110e1d1f9cdeccba1c89958041061ded8e8bc2751ec6dad76a305e70c57f9c81a5a65b5116390af4f7bf7053a03ec13f5d60a58cc5ba61f8c46ef6d2d291de490082dcfdf294aeb3a9414d64e4bd6497d4625acfa591627bfd98f0aec7e7def71515c09942db6911d73b96b4bd2d6df03bb729e945d71549d40e4bc401e1f73baf263a74280537692240638619f92645a5ade1eb8151191c7ff8bd715b3c1cd667e69745b806e16d46d9aa680a7367b8fb45a1598631cf3d44c1f5cfcd95bc8dafdb65a2083905a6937fcf21",
	));

	test32(TestCase(
		/* nonce */"627acd79be19e60a36d2967d",
		/* key */"648eec7d142bf1092adf706c0daae0ea14acb12733d8007aca0a3ce6e2389418",
		/* input */"0cfd93b195e37dd15dfae83132c24ed5bfce7fe6fad4064b213b2c31a39e39ddad2f977e904c9c5b055ed03db46fcdd845bbb6ff0ab5a8c92e89295b6801f36ae63eba61fba24a3858aeb36f2da226b23b24d7b2c7d2670f23a9a1b60db85c0ecee584bef1b00e42d10ca17432a74bbb220d88356d82c850da4c09dd5baf413caf8f9479e02a330065fb865489c0f59605d56146ec8434182345de2d15e2a1dceeeee2fe94871d41913f6788738947ed9849ca0ae985e3e19a97bee82b96feeddceb196c9b6012264661945981c279f43db9599a4ef01116f592478619690daa64387290484d21e8d2444751194e1f361fb37f04014a3c7e4b409e5c828d8990",
		/* output */"0502848571d1472ff10bec06c1299fad23a2cb824d88bf91b5447c5139500bd837a2fddc629e4a964e84907c1e6740263f1fef4f5ed41062982c150d9e77a1047b7d86c0e191945e8db00ca3845a39560857fc9e0e4a394eea4ba80a689cb5714c4bab7124ffdbfa8bbb91c3eb3caa1621f49dba1eea3ebf1d547ee337f9085638a12317b86c11aa1525813445107038942fc519eebdc1b98d313ad822bf0b94a054259aa8cf1be4b3a68f974269729941747f9a23fa5d83453071b431dac62274c24f6a32248b0785ff90aad5840fadc89af0aef7553d9352cfb00d3999ffbe28cd9fde7854e95710f4532b8bf5011e518c93361e58d22a2302182e00e8bccd",
	));

	test32(TestCase(
		/* nonce */"001e58b792ba1b9a74663564",
		/* key */"cd9f2cdc1ade505e6b464685219bb4c1cd70a63667f387280043bf2f74030af9",
		/* input */"0d8d864010ce8df1c0179cf0236dce1c100f9c115eaa5294c24a2e1afa27f9d57ebc18f00482be0218d44262bd4db73002ff53c6388f5e333470aced2a42a73b376686c8d02e05ece27cdd8b1e3f675c715981f8b656d68d0e16227b529cf881d2433e4371fbcd933eaa72346e77e688ac80ee95324512c66a4c16338cf38c941b72c21c3d01e005a07c0eb436014fb1ee61806de7e96842ca3217ab8c7607d609dd2f637f9fda8a85cb0549f262c9e4a955c384319a6ad2b696e2593d7d174f5ddb98e2a8d5d12558c18ab67571e9a0202e91ce26d720cbe41a3a6a4f309296ca4d9d9a59a9043dd2e5a707ed7d5034023d5ea06ab14b39b7852e5c984848d5670c6f2f0b189c2a8a4a4bca",
		/* output */"d2a5693c9d503a8821751d085a0837579233e65b691366e4a7464481d22800e786939349f721a815f28b4e47c8889f0814fb95d592d1185e45d6dbcac14ffa4f1d6c79194f2f7eb7323439d9607edf80f01e3a968b483eb93c01d9cb9d3625d21d66927e7aeedc1d9bd589560ed2b61cbed5ad0e0310c8ebe140c64c67d4909c010902d5386efa359ab60a9573493d3e5d8761cfd4023eba23de48372032d4673b5f6ad66cd0dfab02a73aa81f269ae88fcabb3ae9cb09f6bf60fd3575a3046bc6843f444e1e9fb9ff9b991620344fb99da68df09496b40f8b9dfc34e830a87f65710940603ebab554d36e8b4c9228bc9c26c07b828f34cdfdd40b161717236ba325e8c20bd018b324345e09",
	));

	test32(TestCase(
		/* nonce */"cb1f642ce2c770518836a262",
		/* key */"1559ed5a18ccc4c57415e5f0c694d875d182701bdba12e5d24fd09079898f6f5",
		/* input */"07c50a69e168e388caf6f91471cf436886a3de58ef2c44795d94fba6538add8d414d84f3ef0ac9377fd5bed6aa6805a695f3a711025550bb6f014893c664e09bd05f4d3b850771991fc02f41c7353cd062156243b67fce9c1f0c21eb73087a5de0db0578923eb49bf87a583351e8441c7b121645bcb64ef5960fdca85af863dca7ebb56662e9707d541513bc91bf9b301431423b552e2c148e66ecfd48045ecb3a940dd65694d7fc8bf511e691b9cfd7547fe7bca6465b72ff9f1748723c4eb14f8bc1efb2fbc6726115c597a3881e0d5019335daf2e5ea8796c2a8b893ca798c4ef2639465505c4bd492bf7e934bb35be9b66c9f35730736c65fa4c1a2485378b9d71912cb924634a8e0db2802b75728818dc00fc28effdf1d8a05e4de4608bb6a78bb19c377d5ec77dca1b5ad38fded7",
		/* output */"3dff5fde2ca24bf419e13cb7d12368e70449d41f2aa22e4b567f5cbdbcf3257975e44097deb180f2621ec36acf375dad3b7a19234b9856dc6c7842a7f86be00304b41a8c1662a02e8390346cbd0ff6be7bc1ceb821dbd805ab5c93c9c6ea5093249b5dc52081cbbbe1b326e831ef3c6c42fb791790086d1586f7daf031e70a71b54e9134f942e9ce229fc77980eb80c985ee0c5965eaba375d156f9b423b0615f4ca6fd77de28e28f35aba327e4f1b75725730155b7b4d6c5c264bf3d9dc9a16e7ededcc261add8c666278bac5cf0b3275d6d6678060eae30bbf2ce5f63e6a53a450b65aa0adbd1c90cf045f5ddd9700c2a99c80586c5244cf4c08035b6ff630c82cec3a4fcc83860e987898b42fe746939f8b37c814f8dab65de276e9784fb90f0751d3ba0826889e1e7e4fdbf8a90942",
	));

	test32(TestCase(
		/* nonce */"cc72b199d056100933750548",
		/* key */"8e39cfe66660c5c34c19ffc5c4d8d2f608891d6d6520e663cb85a4ccd63db01e",
		/* input */"3ddcd3c00014747903c95e49f64258615455a0b26c5070a9532382a9bbd18eeb19c9fe1a902f5c6baf544c5938fc256d310a9332223dc3c54a6eb79a4b4091c3b01c798d2800418863f2865c1cd8add760e445588576d4a6c945e1d6d50dc913674daa4737ac94d84eb0ff57cda95df915989c75adc97c4e3c1c837c798a432ba4803a246bb274b032db77e5c1bb554a5342ef2e5d3ff7f102adb5d4e282ad800ccae83f68c4bfd3b6046786a8cfaa2b63c62d64c938189b1039ae1a81ce5c91530772cca0f4a3470ba68e4e0548a221eb4addf91554e603155a4592dc5c338aa0f75a8cc2822b318fbfba4a8f73fa08512132705dae792eed6b809c251d35cca60c476406d964187b63cd59333771e37367671d0ccb393f5b8bde77bebc133485ec5c66bdd631d98cdbee78a3cf435d2f824fa2f9e91e89af28b2e155df4fb04bbe4ce0b6162dcd8e81ee8d5922ebf9c957b26c343a0396d91f6287a4af9e11b7fbb5a5a5c1fcdb186365a20617d4ff5037b0bfa97b6213a6ebcf0b78b81c65737378787b255cba03d715fed4addc2c70c1fb4d3ab16f2bff287186c26a164dae2fe9dbe3c4a2e1617f01cae79f",
		/* output */"ecea5fc18dc4aed23359cacb8f79a457512e0a27d9816f353e315519d2b2faf74d14ae8ae5e227b203823998a47a050c363a807f45f610942fed4518b8091b88dff8b2af8fb6552eb654c85d2b6a918bcf56fb898392941d983b1afd867ef840e12313059ed3e4d217498dd511563a939c3c536fbbf8e019deed29262f0a655fc680b15939475e0cee0ce2e8bab5834f7354b93e2e0958a5bc608fab369b6aee3c9d73a6898e402484eac7300150517bbd137bf55762897696a3dc4be74b0c141755ac8f2f6e59f707b1690c451a774c46bbe195d826a6784f8d807b78f8ebc343ecacf37cb9b1b2fdbff6a1237b5098853d783e77515c419894c2628f8b5117042294ee2ed58a33746f9e79b13fdfaa25a75fc95340a89076e786e0ecad7de437a9a3fb3092146d255005b22895310b1252a3e34572cf74665b97f4adc30dd0f34e3216c7757953a4b618a775bbe68f9e0922d75afc80a1379aaf1745f2263afb6f0b37553d9c984f1ef781ea75b1980c559c77565c83f3e0bd7a3cd7cdb594658beb7e5eb940633dbc6ae2f50383beea676cb6c814b17b1d73dd133f544da88ab371415889ead21803c1ffe3f2",
	));

	test32(TestCase(
		/* nonce */"6d4adb2a1c0cd0333c19a010",
		/* key */"df07d78b19202170815568dba3d1db9c1affb97dee19f11affc0d8b1cb224a3c",
		/* input */"93ce72a518ae892e00c271a08ead720cc4a32b676016612b5bf2b45d9ae9a27da52e664dbbdf709d9a69ba0506e2c988bb5a587400bca8ae4773bf1f315a8f383826741bfd36afeae5219796f5ce34b229cac71c066988dbcae2cbcfcdbb49efcf335380519669aaf3058e9df7f364bfd66c84703d3faaf8747442bdd35ac98acdc719011d27beba39f62eab8656060df02fab7039223f2a96caac8649bc34da45f6f224f928d69c18b281a9b3065f376858c9fd10f26658ae21f5166a50fe9a0d20739402eec84f5240ee05e61268f34408089e264e7006a59bb63eeaa629ba72603e65718d48e94e244e7b39d21d85848d5f6f417631f3876f51b76b6c264356d7d7b1b27bbac78316c5167b689eff236078cf9e2e4626a4ae8bedeecbcaf6883e2e6e9304969b4fc7a4280dcdc5196267e9bb980e225fcbf7a9b2f7098f7f5c9edd06f50c8791edaf387ff3e85ff7bee1f61e4660fddd4eaf5ab0320508e3ccaa9823ae5a71faa86bd76e16d862d83ed57bf6a13de046a3095a74a10c4da952b3c9b8fbde36048537f76eef631a83d55d3a13096e48f02b96a5a8da74c287a9164ce03ddf2f868e9ca3119ec41f0233792e64086c903eb9247dbae80e923eae",
		/* output */"bcf49d62dcd1cff9dc37d7096df0c39031e64ccaeea3830fa485edb71b7fcf2ec709a4b327ef9c7d4ea2b35f113a8485d4c236e06b3baccee30e79c6c08739fe5fbed59db30479b56dfbe584a5d79b169b200430ed27072137e940a34170606b31f22095f2151b4d9b901f6337f991a23e4c8997a1ebf5105361fdade1c889b8dc9565e3b33e0bd608c39d725becbb60da8a797186fe0986736112da3d09906442364d6e253e5b27fd5ad72e877c120ea7a11d42b19948f0df5ddabf9cf661c5ce14b81adc2a95b6b0009ece48922b6a2b6efffdf961be8f8ec1b51ad7cfc5c1bca371f42cdac2389cbddcdc5373b6507cdf3ffc7bfb7e81487a778fcf380b934f7326b131cb568bbaa14c8f427920aa78cc0b323d6ea65260022113e2febfb93dcfce791ab6a18489e9b38de281169f1cd3b35eee0a57ed30533d7411a7e50641a78d2e80db1f872398e4ae49938b8d5aa930c0c0da2182bd176e3df56ab90af3e46cdb862cfc12070bc3bd62d6b0387e4eee66d90c50972427b34acaf2baff9d8a76002a20f43c22ac93686defc68b98b7b707d78d0e7265aabadde32507a67f425cbd16c22a426d56b9892bac3a73dd2d2c03efdb22ecc6483f8d1ca67fc7d5",
	));

	test32(TestCase(
		/* nonce */"1552f1ecdd1ae345319d4956",
		/* key */"968498f5dfc2bc49c3a34b7bbe38515d6b46cbd6f8828ce9273f7d14f08923c8",
		/* input */"f72bec13b0f0b6f2317118f14c2a0d8e963b1bd49ae7584e710dbde75bb1e30c79281847cb822a5f3ae4fa56825e511212f17f0d293cfe80f872e6992d304e9283d08ce65ceeacb003b36a862c91282a22536e0b9c19953512a1bf9e20d3e7a8f1a2dff45dec0b9b04c592e88a7814540cf636a024d10008463d0b3aafbc4c9359889149433ef173124866aa6f53526ef3b3f2c630860ecdd08ffd9fc050e95da512cc87f812f9391085cdec5cc87258b8560806a52336d612da7ab05e0f60566b950904aa27c975a48c7d78455728c87f9b53aa4978374ab9592e12c22d9a760e26eb527133534ac5bbf969596b71cde8b4ef3587fa7ffa7116834348c275ad4dce68ab3397521ddc8e54380129cc81b981f9b32db20dddb0ecaa0f1ff7b06495a42b4a800a207b8e9ca38794e2fa9f40546e0e3aef7b5236d7fdadd72b1158714a5ad8d6264df1e75120088e449b9e911eddac59f1f19a795205ab7532783a93159876133b3fe3a518475a545fbe8dd2ac143f33c35d98e3ee13b63606b1e671917ac3ff9412773a3ac47b8c6627b8ba9dde6820f4f16c2ed9cb7d7086cfbb0cf2d7533eff253d14f634ab2aad3fb4289b9a0bb667a6fdd0acd5949185d53f1dd2b96ff060bb44f872a67259100669e6eaf1a7e2b11dd5fc35792db0c44a1127765934a068bf",
		/* output */"bb618ae6b7739a4dedde1dbacf864b0892b93dea3007237d2f6f23be0718bdd29321e6b0fcb6a44dacf0f5c53d91e16165997e2302ae7ebc2dbd02c0fd8e8606a4ad13e409a4e807f331cf4174171c5fff23ca232192906b4eefdf2ffb4c65af78be01b0ba7d15b4341dd5a2edd49b17db2812358c8af0a4a9724e0169f50d1d331936bc2400012a60849876c3ead52cc9fe60173c9992f83f3e41ebd24fe3961835109612994c7620280539d483f91ef9a64c16032a35612a119589efe6357fa35b19531274576e304be75bc7e91d58015792095bb00ce4de251a52b946554366ea7ed9ce9317020ec155ae0071e022af36ad10eda5d671e5090c136e381cecdb8bc179474fabc7dab2d8a134772976cf0791b6cebe2333d34b4b8e2b6b2eab2b5dc7c6a08a583d091df64328cbcde36bc1b81095d82c741a1503c55d833d551a855e098166c5efffb8e4146e32e54abcaa85076ca6660abdfca9e82824217b5d3f23f7ff3455872bc76751480c1a8e3e725365c82fc135cd3713cc0f1ea733754142f8c37716a2a4fa8a6b898215c287565325774c2510df6b49e78cb986853ac5ca532c9a7e2bceb7c0157f60433f29fe29009343d6035d7b5892c77f821b644590615dc505604501dd218dcab789e6f0525387919cf25c7c6d62a8979e39d346decbed2657",
	));

	test32(TestCase(
		/* nonce */"478ca60b970002bca7147dbf",
		/* key */"deedbe3b6c4d8f6e72cd276e60f30f14a0ef91c87f22aa4af2fe3c73f3f1512b",
		/* input */"96eb94e1adbcc0646440c8824a2fc0f2c4b17d9cbddbb8ba8d9dbd6482fbf7201c74eb923153e0138b2f6f182f9c3d5656ee40bb7c26a01740b5c7d125261d4e4197614800aa152b402ba581bfbf4288e73c9ef7e7e37491212b921420eaaff880eeb458e3d0aa108b01b53492c97e328e9d10e3220b924351d583c00e76aee9325d6b89b1f162ffa30b386b37b5eaf4dfc25d22987dde4496158818c4d8f19ea300fe140be921d3f1abdaf9ab8946833a57cda5f41f995ff80e98b0f10f7afd736dd33438dfd395547f11563056078ff8f7c202aac262955f0ca5dae2365472de40f069028104ac552ea5a45ff2773335e5d3242f1e62e0e98003333dc51a3c8abbaf368f284536672e55d005b24b7aeba8e4cef23289adc12db2213aa037c797e7e753ae985568199cfe14cf1704fbca443e6036bdd05859e3583897cbefe7a0cf268b75d554b2da6e503ee04b126fbf74eaac0ebca37e84ab9c726973af780fe2bc9869fe67b7d9e4a04062ee535b2c1740d1347224e211b5cd37ee14c3325f40abee930eb6a1634986e756b3a1f86a3d7ee7184d95ea948506d8ab8b23f92ecf3eb0586f7a8b1bc227e08a0e32ca75ca4eeffc5c0a2a623547788bca66f3dc2c48671e462544d52a87d34307a7f111aeacb7da50262deab33d9f29dd6b47c3bb555be598d619cc66be8c4b74b01772725268a43d467f39bc565e5efcd0",
		/* output */"590965d18ebdf1a89689662cfae1b8c8a73db8b26941313006b9b9bd6afa6a57149d09a27390b8883069e4fc2dfcf75035def1f8b865e24c21b1a1ed3e9f220d7b48046577b661bc92d9888a912984ad415ea2fc92c9e37da0bef5c7dab11495c612c27b5babe6eee28fd26482272fce69ca7f11bac95251735ad808365ac587830ec04105304f8e440a4da47d30e788718da4282941c9c76f18de4f954b8be750b54cb1145489edf273625a0df9a694a23fe7bfea12579b53c3b2a3de85705568cd7e603f3b8beba9a14cad9979ea283a8a291d3e1105b7f890e2a569804d9b7dd4c7e50bd0dcd11223fd7247af77f04212ece1b98c238d2fa0386a994bc502f83dcdd2e5a0d45b185155e1a395d91726d383c2c198fff1590e983c65ee041638510787c8c59c2e96f31678226a033e027bb40c416b73c3dbef31affc93a659c8ec7ffeca313fd5283a80533b2d63941c8f245d22b160c5fe57c5fa4b759c407b9acd6d9c4f80f244360b9acd11e2b43d4af757e16a6ef9d6756df39ca3a8a235e74351f50b2ebf54df633c8c400fd80b41b07117676d486377095660f2f20f62c034563b4560b473a8f4d6a740306d2a822fd8bd98012a840ba9b1709df9a0d61ecc305f7180fd764e334045d9a8ca23cb8036c05616a8b21fc488429ba4168c59dfa231f0ffa668a3be7b16583df1a55bb9c15d51660ddeca730d66f7a9",
	));

	test32(TestCase(
		/* nonce */"54df19942a3f5904d66dc071",
		/* key */"4077517b5363e841089462edea2ce35fdfc56bb050b3c9ae6f2a0cc04ff4aab3",
		/* input */"be3f309c6e7b89e1ec4a855cf161156d09f8a04d5630534ee19e9e071e3f4603f23f0c59a7b7f8a32c4c203ec8c129a268faba09abde7b61135c6c37fd091e2d695f0e242488098ebed30c7d321f4dcef0bdd23fa85a53569868cf2008bf4d2ee7a12a6673298c7e797321b9f4559748223b590e6fcf17aa72251586b01181cefcd32c6a1a20a0fc27143426f6572b1aab0e7301e390cb857f912d78d5153906c698ee140b36cdc72693cc019cb7add747ca3a07b2b82a2332bfa76c962b186ad94209fcf590ed0f6a73b08a771a58eb9649f2f1da4f7c385da83d50c939231f745514d14b0920deedd9c4dc6d2e547f83643d13541870875e52c610372b14b602e7a47f0b3721cfca60ec68e2eee91f40ceba2d0fdb4ebe19cb1d1ab170726c9e600030454ef355f9a40033672be520e528937f38e7a862a5ae50cd94f667cd015a72ee3f91b1a09031bf4c207e0c516b2e7a4baedf373f1ee71843e560741ed3a3094d2b513e2248caf27ce135716f6887d9f1fe5b11e02c12c989d29054ab183a3f55d9b40d78e12ff56edf936ab966c7c3130bea472b71fd69e70165a76afbf720e2c1587a77943b35acfd81b2ab6f39476623edf3663024fb84da8057ed3a361e9533caf9fc58a5e4897e4bf84f58ed063b5c353bdca3792952eec0a1404149ebeb5b17cd6350ab3e27e44e40fbcb00780d001a48d0365d534ff830553409919608881e665f83bb5cf0736d728c41cc4e985c377f89ee1186303d0d76bc634875ab3ebd87059969f24b0464ae11967bcc47f300a34e3b917b1affceea716c5ad9abf1aa3a1106e2f4d006514dc62cfd2a52426968f2f3991c9f9d8fcd",
		/* output */"e4032c01bcece73fde73961ed216820dcb44ce20134678c98afb674bb03afec2f4aacbade7f87a32fff57ae9213eaf0509e9d9db1313b06fd1df53561f85896ba627cccd2d0e2ae4f24f5579bf02f6599f5e63412ba084cf53a5bc9a8061b5c029b755329fcd73f629fadd3bcf6cb4c572fea86466cb5159d19eaaf0f44c3471d0323bc7206bb514ed8117a61c6d98d44faff6a83716657531d965ba3efbcf067c452e0d2807db3423958d9a4421886fe132d7c47e82086db9507616b67f0051dffc1a49ecce3ca8e4d5f5af15684cd8837a471430ddd333ea0b6ee603b7d9e702692f857fab060ccf26f2a8e61dfd3b12923acca78b83a6004e4ff09113becf6bdd0bec3a449a195559dfeafd4e2a79ead5ae3c993a15ad9b1a2ce818e18edb010b7fece9aa437d85ba9841d89026d6aac1a3a6ab6dad932a26d7db6f3664b06d51584cf4d22a75c06e2840db7292798306e4d39379af85a6bc8dcaebb5246e07fadd5e336f122de0ecb99ca24a971701a1f43bd69933beef6e52d299b132e7510caf27b99739e32bd272afc36755ea80cc7ed3957d91325584b338d15b19fe554ee70bee903babe21d0cbecd49235c70a3a4f516ce16761d1cfcd70bb4b9c7c73c359f3fdd0753d6c1ac1a1463142f18266b6a9c84675f247d56563646fb2c8c3b6b81944c2ba2b76b685ba5ea40cf539bcf3850a8af3e0a69c0b38164de520a3bea82b91f67d36bbd87877b5be7f06c2d26b2dc747a26a51f51fe293197db0e91e6ac617c71ddc6edfeb7db8f067ac2012268deb7e5f00a640c1bbec5c4c71f10f921071308cadededad5c90e72d744d0bf790b043fd35729570889ebe5",
	));

	test32(TestCase(
		/* nonce */"90bece179b25feefcad4f9bd",
		/* key */"e8512d17c6f5805b38e4c9b9c01961a523232162896538f5a37970de43e66906",
		/* input */"0aa4fbce7e1774f0607e7ea01fc0e6d210bb283964ae75e180a9f6ff3d2c4d50914bfc32bca6d243eb33551521d54d66f377fdc1d31974ece79b157905ff7e7a9b064f349727ce37c83c15ae13df635c3e6b4baf994d9aa0bb90b06c6cda51deefda72c97a2993448e654b746b216d2b949bff1af5238558205cfc3162f1d7a020a919db4d4eb44bcf7b269d4df57e24133d1e540694b9148444cee16e64035ef006a6079dff449949c1b342991f2a27f21c8bd74ccf4bc944284a46e9fd9f9bfd4b95f80c05553950fabbf5e5aed6babb8427832266aa4d175114de9127ff6ee848534d6dd5aa6d2dc361319863cdf32cfb1b074faed17d368964393352df01fe8d86af0e994bc9dac315f7d9efa7bef47a16676cdf17a535ae71d399c4c11a3a3ba0491e8d41f419685258a4ec7d1ae588b3ca341719c0827ce5f5a653959a8671844f2d0293c09bc7d35497ed18c160fc7b6d073a311b621a7a37f7ded1df3d73dcba1821278c9e17a191997fa4dab0802e1ee1b468e91e4272c4569a17dc0b2805b980bde798640aa328a3605abea1865083d7446e960c27f69d32882a2a2295efc9c440dc203872373411925f8839715e9441d31dd9cc14bab09a3e03b4a63e14db3039d58725796326ea6327f189beecd63955f1409467c81f4691ecfe9f0ac5234f23dfb84e3199e415ee7b4f67189e8857ff6cb3f64c2ac1b554bfbd679a6ea8491cfd69d96d08ee2744d9103e0b044212560ff707974b1a9043e1f2c3592828fde8ab5e993652c00e2b3fdb19082611b67866ece6c4a2635f87e04d2136d679f632416b03ece4d7e9406f3437163f4fe0c8cc7b87d487f6de3b3022665bcafa847c2b9199e1ba9af7deb0e29b66ad41688d03a8369416dfbee6d03526adb3ebc4b4f8531d73589499a3010b5309e9d9d2f5a9cf347983a92722dbf6c4f0bae8aba57b37d322",
		/* output */"a31f9a532f35f20ba604a9ab9989260e5a4ed04e6ecfa1cb9e0e1d16943906acbbb4e761a2bebc86cad0ce8b3f26d98b455e4b0835eb8b43791cea29fe8fa6e5187b60198142059bbce98917aa2957ae2555bee70e6e9e21ff6197a51ac2ca2952c413efec4d9903a2f6883e88aebe7ca8316831f6a8f2cd0e486319b58dc8db862779adff98b7f35c33faa53d56acd7a81e0feffc286b728f3a11afab7cace4c30b1a45780276b1f0ab89242410d07cb1191c7b9da5d09db7c9a729d91ac3ed82f4350f2871a12d125ba672861d1b0af7219c360a0e023a8b7c23fb9d72631c72e032c097118d90e5db0576586d8224165a8376fe8d04de93516848e7c2653cb4f7d24a971ccf4f16c527ea5b4153fad5fd5bf473b15806671854507bf1a6d9e5fe4a6f6ec977197d21d69a041dd955e199031f895adefd850c8b0ae327ba0c18ca1783560e1ff0feb2f659137e34a91e9e9ff04fe3375b7db6e4326986e6265e5fef00297f6ae627c7563846e531762748fe8d0b6baff17acf1e6c5cfefa35a95ef634ff96f83f16342a6c62311fc653d314f8a6de109356ab7801316e69a48834cb6325816b1f66d5c67d6e9c9cbc8e1a0521fd6e4bf77a7d2609f99c9579e143f530677b99d198a97620d087f058edf35eb7271701ecebb8bfde5671641ed21aeee9e7db06b932e0def91be93cf2955159e9666c770cdffa03886eb6e98dfca8f91ff5cef1927c0f82b9226d65c68d011416cbef802c264e34244ead7a6ebbe28a510a37e1276f4f3cf27a3944a08aaa23bd321092761627dae20dc269b6150545c75e995cfee0a9bcedb1ad8b364beb8839fd5c9f7984fa0a08a1a354aebe18f62acf6d6664978fcfda2ce6fc16eaa2cda5b835339001b3b98d3a407a3e18e0ec2da6ee3d1448c1ece2ed67c3f51f01e76ed59f0e61102b103a3c65aea94275e8d1f0d331538efe",
	));

	test32(TestCase(
		/* nonce */"09bdc9b17d49e6db953bc716",
		/* key */"e5d9f90b68e6ed2e95ca1d636de3334244e63fd8891fb199175705ef5f69e91a",
		/* input */"e097b1e8dea40f63714e63ab3ad9bdd518ac3e188926d1086a9850a5580affb592f6e421abc617c103479ba39a3924eea1c0bbbb051614c4b5003bbd5fcbb8093864fc1c130748194d6b560e203b889b98b574a98ec3e0e07cb2d9f271ba7794e5419123b4f2ebc7e0d65cd404104868905ff2c38d30c967fe9d77ebdd4b8fa836c3b0ad15e3e70e9a28236d5593e761e694b047f63bc62c7b0d493c3e2528c8af78f56725172ac9416ec2bdc54de92b92a63f9ccb61e686f9249c7cc337d99b2160400bb5535eb8f8eb1e3cafcbceaa821c1088edbacb3b01b5bed977e702de747ad00268ffe72e3d877dd75816db65b5459607cd1b963fe43bf2405ec223ddc0de514d59cde74f7522dc72285caa3eeb7eae527a7723b33d21ce91c91c8d26bf36eeb1dcdfc1e9e475c1565ed9c7e64ef601874a4f277280a5ceec26717e9385aee8b159379e3feed7952b87240c942970d63351259aa7a286ddb4a2620fa67565c92f592902e49422f1eecea2f44d1c0bbbf54a9e5612b86a9549aa3e6639a924c7bbe2d3c1b5669da73c0e2c6f6f6084f54a912ad2635d0141c2f5ac925414dce0da09ab8f86eae2a7b7e48741253189e5fd554d5c04d9807ac6ffd8a4f8229a3e8ab75ca5c778bd7ec5a5c02085faba9792cbc47f9e9311f3444e6544359769e1b3eb4d42ac8923ec94536e1a44497766b5da523f5763749dbc2738dfa8e13c191dfeac56c7614a96bd3ae23e4e6e5ac00be851ac9831108989b491eaade62113c531385ef3e964ce817c8ed0857adca946467682c2f4387fab2f31ce71b58370853171720268459588d5d216faca58d0bebbd7cd83a78445d9b49e83ec2cdb59b5d760880bf60532178d60372752b47d52562b316c7de5c74af9cd588643002d66bc6260595a540d2f82cf2c07fa64e0cdd1f79877b6a25b0608c735a7d35ca10852da441fcfb31061fd7e482a0989866f9eea8b0b39c3d519715c1c2766c3ad99f041143cdb36557ed647403458155dccbb80c3a365f0a85b1135695648ab67ac76b3d219c7b77e49d735c72ac947b1d7eeb279beb9d2602aba7b36ca",
		/* output */"7b6e07e6415660affba56047b988f4548b308e7a642c76791f5c3742cc4cb744cde48fc30e50d458084e06c6dd29a52cb4c306a69a493a17c0838d14b107d07b81c983a2dbad09b80f087ba48465a8beaae5b16e8093e17cfb9e84ea3bdb9af00889268a5c01ddf25af434de56f65882322432aa275fac8519e317ef4d89478f29182143f97350983050f5d37c4b518611da6fa2aed7bb73e614231a194fe17c9073e377fc6ea0aa491e15ca54808e0536c8c3f1bf657283f807ebfc89b55049ac8fb86f89f17974fcf0afc1a2c690c0442842d0f4af9ee29dd960e499d1077bfdad4c0c9189a6e83799bb585acdb853c1e99da7ce9c7eeb9bf431f8d364d0ea80b0a95a7807f196c6ee69fe90e6d1f5d23e5cb256e37e65826d7a111f2272884d6319f968580b3164b2697ea6556816cea3ca316651fe2fd68dfa905d080c28622606f7d24da216289fa2c54c6f42dc244ecb047512ace62f0801f2dfad8f0218f45e2b3bbac97c2176c842398b16dfa1fdfc9a68b7b5a1e785d2a0cc592bc491f5a69c81127b758ee02c66b81674d3135c5882d1dc89dadcffa06f4b0644df5c7fd65c72611d79be7ad637edd6fc38b39946aa2a2c6d08ca9d3ff9a8ffe2e7989546489539b1a623fa937c468e59e0978602526b4367de277526895aa222fbaeae2084f418c5745d8ee844da0baa47f592970c14cf710f49539c12104a62baddb3382f5773dd18c83ecb238ae2e749a51584a38e394ebadd175bf5c3cec787907abb1d94af70ae63d3b7d8d5ff254da90b78ec8fe2ea95dfbc6e3e69ecad856c9e54906df8fe39859f2014b74dc3ca0ee2a957001939d37a6c0b489bd3f1658b835a57b24aa282c23e875c9e67e6eb8b32fe44e7d7d8e285d85da0ce1b53990f9fdb5e2e74728e433ed2c1044df9e89cb9bb316c39fc6fc8bcc74a382093926a288170e857d6b7f47858a4c2d05c74263dc9e8199332d0179687f4a4cdfc80ee6737300cefba75905b22d21e897f887b67aa3051877fff11d98bf96ca5091bb225bddd5eae697f3dfb0efcdb788ebf6694b5b39dbb0d4bf9427382a3a58f0b",
	));

	test32(TestCase(
		/* nonce */"3e507e0cdf0d11f88c6c3183",
		/* key */"cdd1a20f05f9e74f1b4c9e2b81c85b11c5bc222925aa603f316dc21363af9620",
		/* input */"0a1064714f20d9e47fe53250ecfec759f4137e60afaf65755f4709a483504c3855833b6dcaf7aa0180fd735fa9a73d46697f6c45004adf12452ea4c04a720fd7c20b9783b74b8b3ea0c8b1563d5a85f44af8afd7d91ca6298ca22642a684f66e365edd6f6bdb2dd32dfa13c62dc497fb341b86f65d40655931171416e23e3b2623c0b4a67d448877b6e3d4e0fe284034a10162b2b5e21639047036874f4bcde22b145b5f18aa8ff32dec81e6a5ac68b3c30c24bd8fd3b8e098a1cf202e2ab2a3bb66a9393222b9f7384653cda7707f00bc3c81e9591fd040a07d3629410c2db78781a4c9db3df5f9d648162f1b087974f56a89db07aa21ba827e3864a1618945b2fba06853a13c35da2909f5013feb313bae09870b8eab904024adab0d6ac46c1a1499791b47413139dee59db676949b9e9ab8d3d6abaa954ec2a9fc83953c91b483c3b6bd6700b96484850734e72e3710a1b379c0d0698aeaf68f13a0d317bfd689471e3299288e7a383a58522f0daaff210cc4917fa05f0b8ceefc2afc46148a05a100d30787accfb4da094e61ea6b58f132692aedcabae928e53c2594b01507b8fc2d0a85a1d111d1f4de0b95258281ae01873a72606753b6f878ecd8c4f613fb3477710d260f0bca0d4c06f675ab7113eded395f88755a98a0ad22b4a002cfe9447c4e39eda13738f4eccb9c13367ebc2878257c4647d31b67e5e32b6a77f23e9593658d19c0a40e8a7228767afba1cf23072b013b2d76ee66e42b57bec2797ce3619c695a661004c8129cb5c5d6a2836be22483f3b7e40bf8ac5535bf6cd065c4821a87829948c88163cfe3c0f60cea4e7ff59df4cdbf80064b2d664b39487413039999b5e86f1d467b12682d0cd355e9f7cd980e87d584ddbda89f68632d3b8fd6bc3b80205d7feb97a46842b093f74aa14bb21accda7474247b5e39ac76ef75e9b5b52b6a829a7e2297ab88fb0eb690d54ab1af2d7437149a6202035ce15f1e6c6267458d62677c263d83d3f8119af191b7d766582620e0f08b411c996c25ba6a32c2d73f592e789ed662e94103329bfa5e6573f1116ec04438997f3e4ad91b4123b570743455020d914bde2d8417fb24671e6db261732fb89dda1a36614b095529e4f97374c9bc0e55aa577bfffa663c816ca9fae3472e0a",
		/* output */"b00a7caf5359c5bcebe590e6bab9aa03370050c55cbd45a257f4869937e922a15f2d38121b1493d6b5dd4a8a47d7b4e5cb049d396ad84ed421df774b0408b6939f18ebf5cf83f48c540affcc2a885967bf4bd222c42904b8a73c4185bde3f97e874fad25b46714235e60c9ff53ed2975c9c85ebad0752249e4b627ffa41555eb9074f63a5f7d61d207d2ce11b2a9fa23a13a0832eccb91efa2afd8d9acfee94ac78a733fa156bfea5006da1d0127c32aadbb75c015b68c627903e1c85bf3a1a9f99c6cfbdbb5c871f7f9661b78cf5e16d819f53e9930e201d4f58e69bcdce77ec5b9b1d2cf206a71f744342273c26b9abc71303c20df3d51f52222893d803fc8e0e0afcd99ee1c7f95b48680403566f7f9e296d7ccc0ec348b6ad515af58d11fd82c628ea29ee6a5d67aaeabd8823addc01a078b04313af73105d4ce4abef8e6ee8ce649640a19678292d4f1017d121549fd2c19ba6cdc0b613e512bc9551d759c6d38aea7e35c0847a142e273a16bb1495e652f9668b97801ba3f6d9931c0a1efaa4452e15732dca1ca9cb45ed289e0fd08d1cee1cdcc9dfba8d0b2562b0b1a180f4ee69d63573222c8d4789bf0d63d2a201a70c7b27c84e620e33e8a863cf49b784269a51ead3d4ad26f044d5859988d5485a11533ea805f5a8f6313caa6b421071a34f57170fdd8e4663e9a4cdcdcc1ddaa9f6e651fb365cf827667b018ae7d028c7f96295b2b4f9eeb4b361b48af86463a79f50b107ab0935e3cec3f4f203cea801ff95fb870d2c2f0e315dc8a6a547dd3c390a1f5403917315164bd2d40362489b389a54e8dc0ddb83e6a43a26c65923e6f76ee0ee0e3a33b0a9066620a01f0319e20b9f1beb3910ad962a3000e6aacb0ae57f3f6c5e0315be5de93edcf0e45e0e47332f9daf7f33e6e8bf1929910b78b8f88ca12bf5519a3217b7554c8c8350cc314561d580bf67a3878e3979430d070121a5e070a3458742e8549bda972f603222e2b30eb8a49a955805307e6e02f8c60a08188f69340e116422458d4a8841f46a78c833b1a822e3f6c9c97422c918f17c36175ca4b3d1c081ee4b175b4b07bf101c3836eb5b9e3cbd08a89b4a1c50edcb41ea8ea6ceb1532f5b842715d50dc21e2499e08c373d3dedb96bb477c8802ab7aa957e0b5810f38",
	));

	test32(TestCase(
		/* nonce */"c9da02eb6ca0cba74c76240c",
		/* key */"574a41e94695e2d54c2f5e1a464c6e801f8d09481aca51437cd93e05ca95a4a6",
		/* input */"00fa3b13b5cfa9b5d65a41cc2d3c420518802c22c4582873f1ad52a22032d2cef7c975078b199787e852fb1f914529f60d1cc854e5d6d547216dce043e0fc94866bb2193343c3a07fde60e668266d1cee3067c6f2ce0f9f63456ad08094b6c7f515f7ca90caa96494e2a6835ba1f3f166012ad1ff6af6b5f8455d5c26e72402966af9066ca70ad027eed23b0eb02c751195064a62283975efeb29bc5993f83360d012a2f5275ac758a9e8fe458fc7cc0673e6b9e338678f0faff60a67fff3784c3054dcbd95d1b00ed4c6156b3831cc42a2ccdeee55541f228b88e6c318e2d797c6fc035ae12868c4a4e3843b5b25a530b1477dec3f5ac27644476b5766e0ee132d833f9a63200eb0980bf72c3666150e567e01e3e1f469cf36beea65946fce714a3f354983e54ca4315b57ea35c5f48bd5eada05f49db1004cbb39888ebab3afad62f6509abad77ca8c4ff28731c7ae545e6876c8f4a80b6cc26928ee05001a9764694b52edd605e182d5a3a5fd192bff58aba90f57e4debe612d02cf6f08af33a78ebf8823bb3eb46d4da25b7dfa15ad436c380633d3db3d0dc4dfec6c2324d105e7090e65342b554854e777b40b5dab8125a58e8b212364ff88459a8466ff5ae661034abc8286a78ad5aa582e2dabbcd7a0b0cedcb9fd5f0bb8c3bef9117f2ca6520a72b94e528c1a4a464398e654995d5f4c77cbabf2b204b96a058cf1b38284b34e41ac37b05a003ed51be9602050f21c6b9326714bc425c1e22833da95a6e77571691d4dcab4ef9056c4c7f85d5b445b902eb375b5164c6bdf629ccfd4127a6c024bb6c4da0b6b08350432e58f8229e04e2e76f704be17d36e0c04fcc7a98f721d4572aa7f66ae8e9664300a189bc3862da47b60c8b33424f6d577cc10f4755f36c2a6decc30ba81bf48f96616ccfcfb74965d6bdcab82728bb224c560d1cfd7a175413ad1c14c734746be3b062b4e7514e9075c688103515e32e3335dbd272a315024d56f4ecd354264da9bc712080657b2b51b06dc7c4c441d9858935a4c3e6b207bde38ea83bba4c6854b2bcf914d758e0a174c0528e0e385c7cff355c38db1c22440369141e91266824c59f1ed23e7d4b99d31b0baa7bed4526e24259dbef5c9ae275e97267b756645f804c274d65ac7ab0f7683435bc2e4f24075cd1b790aa2b53fbf044e8f2092bdf0dbe88a582ff8f8de291e8220",
		/* output */"bea32587095caac661c3ac49e65654b282192b2addf5b9a403aea6c8bd0096291a0a66ca4062acf1da91fb5749952096ec63ab652ecf94c29807f0aaac939b6896edcd6f0cd8dd8d208b906ef4d7a8766831fecd6ce98f4ea0c34fa9a5114dbeb23c2cd6d3aa962e39b18cb343c24e65d49fad0a0fb50736f8d2b24b011108932484399f4c4510ac9a5e6bc78ff0b450e67f87b49f253b99d95d6294e15a9934fc8b89a5913c08f75d3516766fb0f60f82e2b2647b4619991c78adbcf548c07c0dda30c629349d84f298313c3e629e03760b1cf860264205a950d6fd86732a6513827f72c0dff5aff96f7203464f60849c1065beb70f282cca1334f6f6c767dfff94f063361f592e85597de5d313eaed17bd533db24818d9ba9aea2afa797721fbd19eea7b8d46bbc4b9dc0164636d2e754f5e9e8c04e2a381096331731c645ea1f613a37bfa9a6fb2c6307e9bacacbeab7f5672163ff9742a8115049bce0269d7d5f6f35787be031dbee1535b0516ec0b46d12f5833cde5f2cc569edcdd20993e9776aacf48ace7bfadf79065f2803fba6b2b27aa622abb7ae023ff2b27b727f509f313f92026392485a5ed4fd53b2e22b2d2dc1538ce158d34921214638be30ae054a0f5f1d4f9c590a2d215ac2a5b23ed33871ab26c8bb6db7fe9d6f51e527c9547248a4e9734c64658b22893f4f6867a35f18e2bbfd7d62142025955cb51af8e40b6fcb91c7e959cea2c92022c87c29dae107a306f41b00e73c7bceef8cb070e8f9e830caeee463170e919cba6eee63092a5a7ee33b74db09cdd022fdafbcd5d524253a29a103ba6f4d668d31d18f867557871c0e0258221c3050d57c18bdae4cc4ff8da0daddb5c08619be127ee76a317b59a9d8e67808603a1bfce6b4e0d070082b283bf9c0e6ef8256208e482f3e2d1a40d30807f60a868e2279dfbc3586d44ee25fdca3505cd39fd469c2cd03bc2f921d22a8346750f346c919e7247301c1c8a4a3ddb8eabc6e80d85cd2459afe1cbb4851ea2c86b8075e0fef3177cb074894410ecf681242fac62b5fa4ed3a10ddaa595427851d376cf69e350207b667f7aa26d003f1ec739a8792532ebd93f3cafb1fea40d227bcadda2fb6da794cea3371240f257f80b1b8a857ea453b46938397c1f4b303a46257750003a60666a11d03bf2afb5c71e059933d617288891733b63784bd9c662234f",
	));

	test32(TestCase(
		/* nonce */"a4472b3c13c814f614706fa2",
		/* key */"183dbd3967cdaac9b58554cb226a532087ac22bb80a59d1c2e6b997d61e46f45",
		/* input */"01847d8a97d56e55e12f89adb13c8c0f9dea5555e8dc61171fbb8e181f6cf846a4dd68b2c75335c0896fa215bf7f9eb7e398e4520aaaf33461ecfb61051f43d43569fb75fabd79d319bf39469f951e4da7932a74624c46d8d26a9499c701c00d3dea57a6f65b4c0f33b568d13989340294d17cd005b26d89cf6fa1c88e7b6ef4d074291fa8c117ae05d7c785459ef4561c45af63a811e9aa1c31b69a5bdac2356d955a0f579791247a757a691b3de447a53619878397cd82a74053f06da3574045bc856500ec01fd2afbc64d8dd283ac876a50e9396f78c424ab157f481316fd9c90cd899f5aca46dad32c68f1d64ea7f1c4bdb994ad847072609bd89adc2fa8382a5d573b680533640b8321b6adf27926274660b2cbaf04fbc9a4fb17ce8957c38c7bab1aafd5bf7263171e47d2e1ae5cf0494815642209d303dba561754479c24ea01a573c9083b68acc49907b1748924d3c6a82feb9417ca932578c123f9db35521c0d992565f7396f0c23e436289c1720e4e7c6e285c04a8159f93e06801334e523b18fe188355cc6a155febe64ba053e6b5d1cc87787fd5ae68fa86d8c51868b9f6a9664cf0d56aa6cb8463362bb671e6b8423bcbefe2a1a0acba3f135496736b5cec5e329494af46aba322bf5d1cc108c98298459558773a316e09b0bb960a26f4b0bfbaa493b5f98a0e522b6203c471b10e662abe9b9e60de2a1517843933add02017fadd62608383ad53796159f3d21b2c8ed7295802ca79ea65d550114ca2bcc7f7c3b4c6709fffc3c2de00da06e83d8f0cf04b8c8edd21c0fc11a0b2aa7f6adad255fef25e5c0a9d59546e97446e1fbf6a51a8ea6cad54cabfdd19cd10d7d33ff0549b710557e3931821dd8809ab0a9d3aaa761a01ae0f2e378906672924d6a1b12fb1cca7bed41f31974b9917a05de60c32796f502e7035a2c01cb49bc8e1734b9fa138b81b4dfe19d37f5942dd1b42f03e1e5a6a046ecd457174150e17dd148e4bfea44b72da35ef42a7251244700e59e702033677d42611168fd246e1b18b9a464b6c20fc7fcf6360cd00466ece059a69d7d54a4f5565d08799f85dd3c849a08ba43415077c1c0e5dbdba52bb3167ee99a11db551f0260493be1dde58d2072e8c02251f4f574b6e115cbb6136dc2c3fbce75fdcefe812d9c07a91a89088985a52cb1fb9f6cef80fa30364706414175e42c75e8e37f6e7cd028c99f59caa88c49db5b46e8d6301bc39034013718a9eeef5506415016fb21d70e46a03b4c5ba72f91dd9321ff5e210e5e5f7b0723a3bc4bb02b5a74c1f4a63aa5a993a31f79a768fe8033c9abfeb4deb536af1054be02d8d1c4a6a0fa75f3eb787d57a03b7ae994fb1b54b2c43b230ce32e6245d944b3cea4fa6",
		/* output */"785dbea5d1e50af4743ed5fd2209e441fc7c50bc7f6fd9cc7f24654c619e2606178dcbbd81a1f94c1b3176837024098bd31326145be326b32fd9277a55a6fb38780c8dc8b471a3184379d90da4aa87d80b889b1f4d8d0755c1704a526b99ac829b8ad157ca54b2b05ff8b2917e27b0c147ab54add9a89fdcad7b93ba1fe2d5be9de88b68a5324f1b42943e45ee31c4ef783ec9e2337b3f2834b10cf452b313fafdf0c03719140f64060da0a565e185cb8e544e1c185ca230ff2321739a285abe8be4be0ce76678a7b0902a77a645194de49fef8ff64cc464ea25e1f1d72c775e450f08ddd7680d27a4142879787b198583d93b84cd87fd5b4063d92d13d9c9cb580c01fac0174686a18f64e6fa0b3589624cfae04aad74950559bdf92b2b199c60cb04013aa0ef56d1f9ec5b7e968f6a83756ecc9cee7dd8b433f64649f948df5474a64549e71e46fd8bb16568d21f5fb67f5ed555f2b8aec4709383e8cbc45b9fe47c0434178ad4c6d0d42606d6eef0e21d0370898d1d5d646830a88d5f024094fe9c7a2003ca13d20ab7cd748dc11a22f578ddab416f3500eff3d89fc177b46436108e2e2c7973910cb8454a01c9e9b98f966848325444b2ac205b1ed6919fa76aaf63717574761b7f62b10649357df49f85a845a30b6acd57fa202fe58673930ec59399f537e9682b1f5f6f409988789a8e0c1f803478dded14b40d3b6eb3109758efeb6a7fe21f41c4dcc8027258da27ad74010839dbfdf8fe55050511f85c321e653f76e55f22248f46da529a380c6b1a16a19ce73af9715545c2cae098dc42dd61248dbcf7b295f4dc6b8930b41baeef677156c534869be65e723e1aa0336e8be8a3b138f840c9cd63bab6d9d61f239a47d8cf56258544e6ef65edca27069f7a57f087a7cc021fa1294b75c0c0f1093c025e426e4f041ed5187f358402676d5da5fb6ceba76a178f65c8c3046f258531c165b8808bdd221c59ff56e3e06247576e144aac01ea96a07f1be15d7a2b0b3b6c259a9133f8a50b56154ecf9f61022f470027247e6e70e6eaf7ece5e324ec8f95667ffed10337652b119e7cb8d197e306e81ea251340b9fb2c33aa230c0a16e1ca783f9344b3acbf413acd96616e6d477dba90e39326089934bc5ca6620855cdc442e25bf8b8debf335e16e7e25cceb68659cc81b13a507fbd9f30b347126beeb57016bd348fe3df592d4778011664a218227e70d7360d139480500b7f6f84153e61ca4dea105875e19ce3d11a3dfd0ad0074035ff6a9fac0ece91afd8be74c168da20c8baafcc14632eb0e774db758a3d90709cddf0266c27963788c35a842beea8ba2d916234431efde4bb32fd7e1cef51dcf580f4697206bbc3f991f4046360aea6e88ec",
	));

	// From libsodium/test/default/xchacha20.c
    version(none)
	test32(TestCase(
		/* nonce */"c047548266b7c370d33566a2425cbf30d82d1eaf5294109e",
		/* key */"9d23bd4149cb979ccf3c5c94dd217e9808cb0e50cd0f67812235eaaf601d6232",
		/* input */"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
		/* output */"a21209096594de8c5667b1d13ad93f744106d054df210e4782cd396fec692d3515a20bf351eec011a92c367888bc464c32f0807acd6c203a247e0db854148468e9f96bee4cf718d68d5f637cbd5a376457788e6fae90fc31097cfc",
	));

	// From draft-irtf-cfrg-xchacha-01
    version(none)
	test32(TestCase(
		/* nonce */"404142434445464748494a4b4c4d4e4f5051525354555658",
		/* key */"808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f",
		/* input */"5468652064686f6c65202870726f6e6f756e6365642022646f6c65222920697320616c736f206b6e6f776e2061732074686520417369617469632077696c6420646f672c2072656420646f672c20616e642077686973746c696e6720646f672e2049742069732061626f7574207468652073697a65206f662061204765726d616e20736865706865726420627574206c6f6f6b73206d6f7265206c696b652061206c6f6e672d6c656767656420666f782e205468697320686967686c7920656c757369766520616e6420736b696c6c6564206a756d70657220697320636c6173736966696564207769746820776f6c7665732c20636f796f7465732c206a61636b616c732c20616e6420666f78657320696e20746865207461786f6e6f6d69632066616d696c792043616e696461652e",
		/* output */"4559abba4e48c16102e8bb2c05e6947f50a786de162f9b0b7e592a9b53d0d4e98d8d6410d540a1a6375b26d80dace4fab52384c731acbf16a5923c0c48d3575d4d0d2c673b666faa731061277701093a6bf7a158a8864292a41c48e3a9b4c0daece0f8d98d0d7e05b37a307bbb66333164ec9e1b24ea0d6c3ffddcec4f68e7443056193a03c810e11344ca06d8ed8a2bfb1e8d48cfa6bc0eb4e2464b748142407c9f431aee769960e15ba8b96890466ef2457599852385c661f752ce20f9da0c09ab6b19df74e76a95967446f8d0fd415e7bee2a12a114c20eb5292ae7a349ae577820d5520a1f3fb62a17ce6a7e68fa7c79111d8860920bc048ef43fe84486ccb87c25f0ae045f0cce1e7989a9aa220a28bdd4827e751a24a6d5c62d790a66393b93111c1a55dd7421a10184974c7c5",
	));
}
