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

module pham.db.buffer_filter_cipher;

version (unittest) import pham.utl.test;
import pham.cp.cipher;
import pham.db.buffer_filter;

nothrow @safe:

class DbBufferFilterCipher(DbBufferFilterKind Kind) : DbBufferFilter
{
nothrow @safe:

public
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

    @property final override DbBufferFilterKind kind() const
    {
        return Kind;
    }

    @property final override string name() const
    {
        return _cipher.name;
    }

protected:
    override void doDispose(bool disposing)
    {
        if (_cipher !is null)
        {
            _cipher.disposal(disposing);
            _cipher = null;
        }
        super.doDispose(disposing);
    }

private:
    Cipher _cipher;
}

class DbBufferFilterCipherRC4(DbBufferFilterKind Kind) : DbBufferFilterCipher!Kind
{
import pham.cp.cipher_rc4;

nothrow @safe:

public:
    this(CipherParameters keyParameters)
    {
        super(new CipherRC4(keyParameters));
    }
}


// Any below codes are private
private:


unittest // DbBufferFilterCipherRC4
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest("unittest db.buffer_filter_cipher.DbBufferFilterCipherRC4");

    auto keyParameters = CipherParameters(cast(ubyte[])("abc0123456789xyz".dup));
	auto encryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.write)(keyParameters);
	auto decryptor = new DbBufferFilterCipherRC4!(DbBufferFilterKind.read)(keyParameters);

    enum const(ubyte)[] original = "the quick brown fox jumps over the lazy dog\r".representation;
    ubyte[] encrypted, decrypted;
    encryptor.process(original, encrypted);
    decryptor.process(encrypted, decrypted);
    assert(original == decrypted);

    encryptor.dispose();
    encryptor = null;

    decryptor.dispose();
    decryptor = null;
}
