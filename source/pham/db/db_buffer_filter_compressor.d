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

module pham.db.buffer_filter_compressor;

version (unittest) import pham.utl.test;
import pham.utl.object : alignRoundup;
import pham.db.buffer_filter;

nothrow @safe:

class DbBufferFilterCompressor(DbBufferFilterKind Kind) : DbBufferFilter
{
nothrow @safe:

public:
    @property final override DbBufferFilterKind kind() const
    {
        return Kind;
    }
}

// Use default defaultLevel = level6 & windowBits = 15
// Firebird requires to have rfc1950Header (checksum)
class DbBufferFilterCompressorZip(DbBufferFilterKind Kind) : DbBufferFilterCompressor!Kind
{
import pham.utl.zip;

nothrow @safe:

public:
    this()
    {
        static if (Kind == DbBufferFilterKind.read)
            this.codec = new ZlibCodec(CompressionMode.decompress);
        else
        {
            static assert(Kind == DbBufferFilterKind.write);

            this.codec = new ZlibCodec(CompressionMode.compress);
        }
    }

    final override bool process(scope const(ubyte)[] input, out ubyte[] output) @trusted
    in
    {
        assert(input.length < uint.max);
    }
    do
    {
        clearError();

        const inputLength = input.length;

        if (!inputLength)
        {
            output = null;
            return true;
        }

        bool returnError(int errorNumber)
        {
            errorCode = errorNumber;
            errorMessage = codec.errorMessage.length != 0 ? codec.errorMessage : ZlibException.codeMessage(errorNumber);
            codec.resetBuffers(null, null);

            version (TraceFunction) dgFunctionTrace("errorNumber=", errorNumber, ", errorMessage=", errorMessage);

            return false;
        }

        static if (Kind == DbBufferFilterKind.read)
        {
            codec.resetBuffers(input, increaseOutputBuffer(alignRoundup(inputLength, 1024)));

	        // pass 1: inflate
	        while (codec.availableBytesIn != 0 || codec.availableBytesOut == 0)
	        {
	            if (codec.nextOut >= _outputBuffer.length)
                    codec.outputBuffer = increaseOutputBuffer(_outputBuffer.length * 2);
	            codec.availableBytesOut = _outputBuffer.length - codec.nextOut;

	            const r = codec.inflate(FlushType.none);
	            if (r != ZipResult.Z_OK && r != ZipResult.Z_STREAM_END)
                    return returnError(r);
	        }

	        // pass 2: finish and flush
	        do
	        {
	            if (codec.nextOut >= _outputBuffer.length)
	                codec.outputBuffer = increaseOutputBuffer(_outputBuffer.length * 2);
	            codec.availableBytesOut = _outputBuffer.length - codec.nextOut;

	            const r = codec.inflate(FlushType.sync);
	            if (r != ZipResult.Z_OK && r != ZipResult.Z_STREAM_END)
                    return returnError(r);
	        }
	        while (codec.availableBytesIn != 0 || codec.availableBytesOut == 0);

            output = codec.peekOutput();
            codec.resetBuffers(null, null);
            return true;
        }
        else
        {
            static assert(Kind == DbBufferFilterKind.write);

            enum maxInitialSize = 32 * 1024;
            auto initialSize = alignRoundup(inputLength, 1024);
            codec.resetBuffers(input, increaseOutputBuffer(initialSize <= maxInitialSize ? initialSize : maxInitialSize));

	        // pass 1: deflate
	        while (codec.availableBytesIn != 0 || codec.availableBytesOut == 0)
	        {
	            if (codec.nextOut >= _outputBuffer.length)
                    codec.outputBuffer = increaseOutputBuffer(_outputBuffer.length * 2);
	            codec.availableBytesOut = _outputBuffer.length - codec.nextOut;

	            const r = codec.deflate(FlushType.none);
	            if (r != ZipResult.Z_OK && r != ZipResult.Z_STREAM_END)
                    return returnError(r);
	        }

	        // pass 2: finish and flush
	        do
	        {
	            if (codec.nextOut >= _outputBuffer.length)
                    codec.outputBuffer = increaseOutputBuffer(_outputBuffer.length * 2);
	            codec.availableBytesOut = _outputBuffer.length - codec.nextOut;

	            const r = codec.deflate(FlushType.sync);
	            if (r != ZipResult.Z_OK && r != ZipResult.Z_STREAM_END)
                    return returnError(r);
	        }
	        while (codec.availableBytesIn != 0 || codec.availableBytesOut == 0);

            output = codec.peekOutput();
            codec.resetBuffers(null, null);
            return true;
        }
    }

    @property final override string name() const
    {
        return "ZIP";
    }

private:
    ZlibCodec codec;
}


// Any below codes are private
private:


unittest // DbBufferFilterCompressorZip
{
    import std.string : representation;
    import pham.utl.test;
    traceUnitTest("unittest db.buffer_filter_compressor.DbBufferFilterCompressorZip");

	auto compress = new DbBufferFilterCompressorZip!(DbBufferFilterKind.write)();
	auto uncompress = new DbBufferFilterCompressorZip!(DbBufferFilterKind.read)();

    enum const(ubyte)[] original = "the quick brown fox jumps over the lazy dog\r".representation;
    ubyte[] compressed, uncompressed;
    compress.process(original, compressed);
    uncompress.process(compressed, uncompressed);
    assert(original == uncompressed);

    compress.dispose();
    compress = null;

    uncompress.dispose();
    uncompress = null;
}
