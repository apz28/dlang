/*
*
* License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: An Pham
*
* Copyright An Pham 2020 - xxxx.
* Distributed under the Boost Software License, Version 1.0.
* (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
*
*/

module pham.db.db_buffer_filter_cipher;

version (unittest) import pham.utl.utl_test;
import pham.cp.cp_cipher : Cipher, CipherKey, CipherKeyKind;
import pham.utl.utl_disposable : DisposingReason, isDisposing;
import pham.db.db_buffer_filter;

nothrow @safe:

class DbBufferFilterCipher(DbBufferFilterKind Kind) : DbBufferFilter
{
nothrow @safe:

public:
    this(Cipher cipher)
    {
        this._cipher = cipher;
    }

    final override bool process(scope const(ubyte)[] input, out ubyte[] output)
    {
        clearError();

        if (!input.length)
        {
            output = null;
            return true;
        }

        increaseOutputBuffer(input.length);

        static if (Kind == DbBufferFilterKind.read)
            output = _cipher.decrypt(input, _outputBuffer);
        else
        {
            static assert(Kind == DbBufferFilterKind.write);

            output = _cipher.encrypt(input, _outputBuffer);
        }

        return true;
    }

    @property final Cipher cipher()
    {
        return _cipher;
    }

    @property final override DbBufferFilterKind kind() const pure
    {
        return Kind;
    }

    @property final override string name() const pure
    {
        return _cipher.name;
    }

protected:
    override void doDispose(const(DisposingReason) disposingReason) nothrow @safe
    {
        if (_cipher !is null)
        {
            _cipher.dispose(disposingReason);
            if (isDisposing(disposingReason))
                _cipher = null;
        }
        super.doDispose(disposingReason);
    }

private:
    Cipher _cipher;
}

class DbBufferFilterCipherChaCha(DbBufferFilterKind Kind) : DbBufferFilterCipher!Kind
{
    import pham.cp.cp_cipher_chacha : CipherChaCha20;

nothrow @safe:

public:
    this(CipherKey key)
    in
    {
        assert(key.kind == CipherKeyKind.chacha);
        assert(key.isValid());
    }
    do
    {
        super(new CipherChaCha20(key));
    }
}

class DbBufferFilterCipherRC4(DbBufferFilterKind Kind) : DbBufferFilterCipher!Kind
{
    import pham.cp.cp_cipher_rc4 : CipherRC4;

nothrow @safe:

public:
    this(CipherKey key)
    in
    {
        assert(key.kind == CipherKeyKind.simpleKey);
        assert(key.isValid());
    }
    do
    {
        super(new CipherRC4(key));
    }
}


// Any below codes are private
private:

unittest // DbBufferFilterCipherRC4
{
    import std.string : representation;
    import pham.cp.cp_cipher : CipherSimpleKey;
    import pham.utl.utl_test;
    traceUnitTest("unittest pham.db.buffer_filter_cipher.DbBufferFilterCipherRC4");

    auto k = CipherSimpleKey(0, "abc0123456789xyz".representation);
    auto key = CipherKey(k);
	auto encryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.write)(key);
	auto decryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.read)(key);

    static immutable const(ubyte)[] original = "the quick brown fox jumps over the lazy dog\r".representation;
    ubyte[] encrypted, decrypted;
    encryptor.process(original, encrypted);
    decryptor.process(encrypted, decrypted);
    assert(original == decrypted);

    encryptor.dispose();
    encryptor = null;

    decryptor.dispose();
    decryptor = null;
}
