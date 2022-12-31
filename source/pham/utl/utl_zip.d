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

module pham.utl.zip;

import std.exception : assumeWontThrow;
import std.format : format;

public import pham.utl.zip_constant;
import pham.utl.zip_tree;
import pham.utl.zip_deflate;
import pham.utl.zip_inflate;

nothrow @safe:

class ZlibException : Exception
{
nothrow @safe:

public:
	this(int code, string message)
    {
		super(message);
		this.code = code;
    }

	static string codeMessage(int code) pure
    {
		import std.conv : to;

		switch (code)
        {
			case ZipResult.Z_OK: return null;
		    case ZipResult.Z_STREAM_END: return "stream end";
			case ZipResult.Z_NEED_DICT: return "need dict";
			case ZipResult.Z_ERRNO: return "errno";
			case ZipResult.Z_STREAM_ERROR: return "stream error";
			case ZipResult.Z_DATA_ERROR: return "data error";
			case ZipResult.Z_MEM_ERROR: return "mem error";
			case ZipResult.Z_BUF_ERROR: return "buf error";
			case ZipResult.Z_VERSION_ERROR: return "version error";
			default: return "unknown error: " ~ to!string(code);
        }
    }

public:
	int code;
}

/**
 * Encoder and Decoder for ZLIB and DEFLATE (IETF RFC1950 and RFC1951).
 * This class compresses and decompresses data according to the Deflate algorithm
 * and optionally, the ZLIB format, as documented in <see
 * href="http://www.ietf.org/rfc/rfc1950.txt">RFC 1950 - ZLIB</see> and <see
 * href="http://www.ietf.org/rfc/rfc1951.txt">RFC 1951 - DEFLATE</see>.
 */
class ZlibCodec
{
nothrow @safe:

public:
	/**
	 * Create a ZlibCodec.
	 * If you use this default constructor, you will later have to explicitly call
	 * initializeInflate() or initializeDeflate() before using the ZlibCodec to compress
	 * or decompress.
	 */
	this()
    {}

	/**
	 * Create a ZlibCodec that either compresses or decompresses.
	 * Params:
	 *	mode = Indicates whether the codec should compress (deflate) or decompress (inflate).
	 */
	this(CompressionMode mode)
	{
		if (mode == CompressionMode.compress)
			initializeDeflate();
		else if (mode == CompressionMode.decompress)
			initializeInflate();
		else
			assert(0);
	}

	/**
	 * Initialize the inflation state.
	 * It is not necessary to call this before using the ZlibCodec to inflate data;
	 * It is implicitly called when you call the constructor.
	 * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int initializeInflate()
	{
		if (dstate !is null)
            return setError(ZipResult.Z_ERRNO,  "You may not call initializeInflate() after calling initializeDeflate().");

		istate = new InflateManager(this);
		return setError(istate.initialize(this.windowBits, this.rfc1950Header), null);
	}

	/**
	 * Initialize the inflation state with an explicit flag to govern the handling of
	 * RFC1950 header bytes.
	 * If you want to read a zlib stream you should specify true for
	 * expectRfc1950Header. In this case, the library will expect to find a ZLIB
	 * header, as defined in <see href="http://www.ietf.org/rfc/rfc1950.txt">RFC
	 * 1950</see>, in the compressed stream. If you will be reading a DEFLATE or
	 * GZIP stream, which does not have such a header, you will want to specify
	 * false.
	 * Params:
	 *	windowBits = The number of window bits to use. If you need to ask what that is,
	 *				 then you shouldn't be calling this initializer.
	 *	expectRfc1950Header = whether to expect an RFC1950 header byte pair when reading
	 *						  the stream of data to be inflated.
	 * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int initializeInflate(int windowBits, bool expectRfc1950Header)
    in
    {
		assert(ZipConst.windowBitsMin <= windowBits && windowBits <= ZipConst.windowBitsMax);
    }
	do
	{
		if (dstate !is null)
            return setError(ZipResult.Z_ERRNO,  "You may not call InitializeInflate() after calling InitializeDeflate().");

		this.windowBits = windowBits;
		this.rfc1950Header = expectRfc1950Header;

		return initializeInflate();
	}

	/**
	 * Inflate the data in the InputBuffer, placing the result in the OutputBuffer.
	 * You must have set InputBuffer and OutputBuffer, NextIn and NextOut, and AvailableBytesIn and
	 * AvailableBytesOut  before calling this method.
	 * Params:
	 *	flush = The flush to use when inflating.
	 * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 * Example:
	 * ```
	 * ubyte[] inflateBuffer(ubyte[] compressedBytes)
	 * {
	 *     auto result = new ubyte[1024]; // Must initialize non-null value
	 *     auto decompressor = new ZlibCodec();
	 *
	 *     decompressor.initializeInflate();
	 *     decompressor.resetBuffers(compressedBytes, result);
	 *
	 *     // pass 1: inflate
	 *     do
	 *     {
	 *         if (decompressor.nextOut >= result.length)
	 *         {
	 *             result.length = result.length * 2;
	 *             decompressor.outputBuffer = result; // result can be relocated, re-assign
	 *         }
	 *         decompressor.availableBytesOut = result.length - decompressor.nextOut;
     *
	 *         const rc = decompressor.inflate(FlushType.none);
	 *         if (rc != ZipResult.Z_OK && rc != ZipResult.Z_STREAM_END)
	 *             throw new Exception("inflating: " + decompressor.errorMessage);
	 *     }
	 *     while (decompressor.availableBytesIn != 0 || decompressor.availableBytesOut == 0);
	 *
	 *     // pass 2: finish and flush
	 *     do
	 *     {
	 *         if (decompressor.nextOut >= result.length)
	 *         {
	 *             result.length = result.length * 2;
	 *             decompressor.outputBuffer = result; // result can be relocated, re-assign
	 *         }
	 *         decompressor.availableBytesOut = result.length - decompressor.nextOut;
     *
	 *         const rc = decompressor.inflate(FlushType.finish);
	 *         if (rc != ZipResult.Z_OK && rc != ZipResult.Z_STREAM_END)
	 *             throw new Exception("inflating: " + decompressor.errorMessage);
	 *     }
	 *     while (decompressor.availableBytesIn != 0 || decompressor.availableBytesOut == 0);
	 *
	 *     const rc = decompressor.endInflate();
	 *     if (rc != ZipResult.Z_OK)
	 *         throw new Exception("inflating: " + decompressor.errorMessage);
	 *
	 *	   return result[0..decompressor.totalBytesOut];
	 * }
	 * ```
	 */
	final int inflate(FlushType flush)
	{
		if (istate is null)
			return setError(ZipResult.Z_ERRNO, "No Inflate State!");

		return setError(istate.inflate(flush), null);
	}

	/**
	 * Ends an inflation session.
	 * Call this after successively calling inflate(). This will cause all buffers to be flushed.
	 * After calling this you cannot call inflate() without a intervening call to one of the
	 * initializeInflate() overloads.
	 * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int endInflate()
	{
		if (istate is null)
			return setError(ZipResult.Z_ERRNO, "No Inflate State!");

		const result = istate.end();
		istate = null;
		return setError(result, null);
	}

	/**
	 * I don't know what this does!
	 * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int syncInflate()
	{
		if (istate is null)
			return setError(ZipResult.Z_ERRNO, "No Inflate State!");

		return setError(istate.sync(), null);
	}

	/**
	 * Initialize the ZlibCodec for deflation operation.
	 * The codec will use the MAX window bits and the default level of compression.
	 */
	final int initializeDeflate()
	{
		if (istate !is null)
            return setError(ZipResult.Z_ERRNO, "You may not call initializeDeflate() after calling initializeInflate().");

		dstate = new DeflateManager(this);
		return setError(dstate.initialize(this.compressLevel, this.windowBits, this.compressStrategy,
			this.rfc1950Header, this.compressMemLevel), null);
	}

	/**
	 * Initialize the ZlibCodec for deflation operation, using the specified CompressionLevel,
	 * and the explicit flag governing whether to emit an RFC1950 header byte pair.
	 * The codec will use the maximum window bits (15) and the specified CompressionLevel.
	 * If you want to generate a zlib stream, you should specify true for
	 * wantRfc1950Header. In this case, the library will emit a ZLIB
	 * header, as defined in <see href="http://www.ietf.org/rfc/rfc1950.txt">RFC
	 * 1950</see>, in the compressed stream.
	 * Params:
	 *	compressLevel = The compression level for the codec.
	 *	windowBits = The number of window bits to use. If you need to ask what that is,
	 *				 then you shouldn't be calling this initializer.
	 *	wantRfc1950Header = whether to emit an initial RFC1950 byte pair in the compressed stream.
	 * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int initializeDeflate(CompressionLevel compressLevel, int windowBits, CompressionStrategy compressStrategy,
		bool wantRfc1950Header, int compressMemLevel)
    in
    {
		assert(ZipConst.windowBitsMin <= windowBits && windowBits <= ZipConst.windowBitsMax);
		assert(ZipConst.deflateMemLevelMin <= compressMemLevel && compressMemLevel <= ZipConst.deflateMemLevelMax);
    }
	do
	{
		if (istate !is null)
            return setError(ZipResult.Z_ERRNO, "You may not call initializeDeflate() after calling initializeInflate().");

		this.compressLevel = compressLevel;
		this.windowBits = windowBits;
		this.compressStrategy = compressStrategy;
		this.rfc1950Header = wantRfc1950Header;
		this.compressMemLevel = compressMemLevel;

		return initializeDeflate();
	}

	/**
	 * Deflate one batch of data.
	 * You must have set inputBuffer and outputBuffer before calling this method.
	 * Params:
	 *	flush = whether to flush all data as you deflate. Generally you will want to
	 *			use FlushType.none here, in a series of calls to deflate(), and then call endDeflate() to
	 *			flush everything.
     * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 * Example:
	 * ```
	 * ubyte[] deflateBuffer(ubyte[] uncompressedBytes)
	 * {
	 *     auto result = new ubyte[1024]; // Must initialize non-null value
	 *     auto compressor = new ZlibCodec();
	 *
	 *     compressor.initializeDeflate();
	 *     compressor.resetBuffers(uncompressedBytes, result);
	 *
	 *     // pass 1: deflate
	 *     do
	 *     {
	 *         if (compressor.nextOut >= result.length)
	 *         {
	 *             result.length = result.length * 2;
	 *             compressor.outputBuffer = result; // result can be relocated, re-assign
	 *         }
	 *         compressor.availableBytesOut = result.length - compressor.nextOut;
	 *
	 *         const rc = compressor.deflate(FlushType.none);
	 *         if (rc != ZipResult.Z_OK && rc != ZipResult.Z_STREAM_END)
	 *             throw new Exception("deflating: " + compressor.errorMessage);
	 *     }
	 *     while (compressor.availableBytesIn != 0 || compressor.availableBytesOut == 0);
	 *
	 *     // pass 2: finish and flush
	 *     do
	 *     {
	 *         if (compressor.nextOut >= result.length)
	 *         {
	 *             result.length = result.length * 2;
	 *             compressor.outputBuffer = result; // result can be relocated, re-assign
	 *         }
	 *         compressor.availableBytesOut = result.length - compressor.nextOut;
	 *
	 *         const rc = compressor.deflate(FlushType.finish);
	 *         if (rc != ZipResult.Z_OK && rc != ZipResult.Z_STREAM_END)
	 *             throw new Exception("deflating: " + compressor.errorMessage);
	 *     }
	 *     while (compressor.availableBytesIn != 0 || compressor.availableBytesOut == 0);
	 *
	 *     const rc = compressor.endDeflate();
	 *     if (rc != ZipResult.Z_OK)
	 *         throw new Exception("deflating: " + compressor.errorMessage);
	 *
	 *	   return result[0..compressor.totalBytesOut];
	 * }
	 * ```
	 */
	final int deflate(FlushType flush)
	{
		if (dstate is null)
			return setError(ZipResult.Z_ERRNO, "No Deflate State!");

		return setError(dstate.deflate(flush), null);
	}

	/**
	 * End a deflation session.
	 * Call this after making a series of one or more calls to deflate(). All buffers are flushed.
     * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int endDeflate()
	{
		if (dstate is null)
			return setError(ZipResult.Z_ERRNO, "No Deflate State!");

		// TODO: dinoch Tue, 03 Nov 2009  15:39 (test this)
		//int ret = dstate.End();
		dstate = null;
		return setError(ZipResult.Z_OK, null); //ret;
	}

	/**
	 * Reset a codec for another deflation session.
	 * Call this to reset the deflation state. For example if a thread is deflating
	 * non-consecutive blocks, you can call reset() after the deflate(sync) of the first
	 * block and before the next Deflate(None) of the second block.
     * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int resetDeflate()
	{
		if (dstate is null)
			return setError(ZipResult.Z_ERRNO, "No Deflate State!");

		totalBytesIn = totalBytesOut = 0;
		resetAdler32(0, null);

		dstate.reset();
		return setError(ZipResult.Z_OK, null);
	}

	final ubyte[] peekOutput() return
    {
		return outputBuffer[0..nextOut];
    }

	final typeof(this) resetBuffers(const(ubyte)[] inputBuffer, ubyte[] outputBuffer)
    {
		this.inputBuffer = inputBuffer;
		this.availableBytesIn = inputBuffer.length;
		this.nextIn = 0;
		this.totalBytesIn = 0;

		this.outputBuffer = outputBuffer;
		this.availableBytesOut = outputBuffer.length;
		this.nextOut = 0;
		this.totalBytesOut = 0;

		return this;
    }

	final typeof(this) resetBuffers(const(ubyte)[] inputBuffer, size_t outputBufferLength)
    {
		this.inputBuffer = inputBuffer;
		this.availableBytesIn = inputBuffer.length;
		this.nextIn = 0;
		this.totalBytesIn = 0;

		this.outputBuffer.length = outputBufferLength;
		this.availableBytesOut = outputBufferLength;
		this.nextOut = 0;
		this.totalBytesOut = 0;

		return this;
    }

	/**
	 * Set the CompressionStrategy and CompressionLevel for a deflation session.
	 * Params:
	 *	compressLevel = the level of compression to use.
	 *	compressStrategy = the strategy to use for compression.
     * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int setDeflateParams(CompressionLevel compressLevel, CompressionStrategy compressStrategy)
	{
		if (dstate is null)
			return setError(ZipResult.Z_ERRNO, "No Deflate State!");

		this.compressLevel = compressLevel;
		this.compressStrategy = compressStrategy;

		return setError(dstate.setParams(compressLevel, compressStrategy), null);
	}

	/**
	 * Set the dictionary to be used for either Inflation or Deflation.
	 * Params:
	 *	dictionary = The dictionary bytes to use.
     * Returns:
     *	ZipResult.Z_OK if everything goes well or an error code of type ZipResult
	 */
	final int setDictionary(scope const(ubyte)[] dictionary)
	{
		if (istate !is null)
			return setError(istate.setDictionary(dictionary), null);

		if (dstate !is null)
			return setError(dstate.setDictionary(dictionary), null);

		return setError(ZipResult.Z_ERRNO, "No Inflate or Deflate state!");
	}

	/**
	 * Flush as much pending output as possible. All deflate() output goes
	 * through this function so some applications may wish to modify it
	 * to avoid allocating a large strm.next_out buffer and copying into it.
	 * (See also readBuf()).
	 */
	final int flushPending()
	{
		const len = dstate.pendingCount > availableBytesOut ? availableBytesOut : dstate.pendingCount;
		if (len == 0)
			return setError(ZipResult.Z_STREAM_END, null);

		if (dstate.pending.length <= dstate.nextPending ||
			dstate.pending.length < (dstate.nextPending + len) ||
			outputBuffer.length <= nextOut ||
			outputBuffer.length < (nextOut + len))
		{
			return setError(ZipResult.Z_ERRNO,
				assumeWontThrow(format("Invalid State. (pending.length=%u, pendingCount=%u)",
					cast(uint)dstate.pending.length, dstate.pendingCount)));
		}

		outputBuffer[nextOut..nextOut + len] = dstate.pending[dstate.nextPending..dstate.nextPending + len];
		availableBytesOut -= len;
		nextOut += len;
		totalBytesOut += len;

		dstate.nextPending += len;
		dstate.pendingCount -= len;
		if (dstate.pendingCount == 0)
			dstate.nextPending = 0;

		return setError(ZipResult.Z_OK, null);
	}

	/**
	 * Read a new buffer from the current input stream, update the adler32
	 * and total number of bytes read. All deflate() input goes through
	 * this function so some applications may wish to modify it to avoid
	 * allocating a large strm.next_in buffer and copying from it.
	 * (See also flushPending()).
	 */
	final int readBuf(scope ubyte[] buf)
	in
    {
		assert(buf.length < int.max);
    }
	do
	{
		const len = cast(int)(availableBytesIn > buf.length ? buf.length : availableBytesIn);
		if (len == 0)
			return 0;

		if (dstate.WantRfc1950HeaderBytes)
			_adler32 = Adler.adler32(_adler32, inputBuffer[nextIn..nextIn + len]);

		buf[0..len] = inputBuffer[nextIn..nextIn + len];
		availableBytesIn -= len;
		nextIn += len;
		totalBytesIn += len;

		return len;
	}

	final uint resetAdler32(uint adler32)
    {
		this._adler32 = adler32;
		return this._adler32;
    }

	final uint resetAdler32(uint adler32, scope const(ubyte)[] buf)
    {
		this._adler32 = Adler.adler32(adler32, buf);
		return this._adler32;
    }

	final int setError(int errorCode, string errorMessage)
    {
		this._errorCode = errorCode;
		if (errorCode == ZipResult.Z_OK || errorMessage.length != 0)
			this._errorMessage = errorMessage;
		return errorCode;
    }

	final void updateAdler32(scope const(ubyte)[] buf)
    {
		_adler32 = Adler.adler32(_adler32, buf);
    }

public:
	// The buffer from which data is taken.
	const(ubyte)[] inputBuffer;

	// An index into the InputBuffer array, indicating where to start reading.
	size_t nextIn;

	/**
	 * The number of bytes available in the inputBuffer, starting at nextIn.
	 * Generally you should set this to inputBuffer.length before the first inflate() or deflate() call.
	 * The class will update this number as calls to inflate/deflate are made.
	 */
	size_t availableBytesIn;

	// Total number of bytes read so far, through all calls to inflate()/deflate().
	ulong totalBytesIn;

	// Buffer to store output data.
	ubyte[] outputBuffer;

	// An index into the outputBuffer array, indicating where to start writing.
	size_t nextOut;

	/**
	 * The number of bytes available in the outputBuffer, starting at nextOut.
	 * Generally you should set this to outputBuffer.length before the first inflate() or deflate() call.
	 * The class will update this number as calls to inflate/deflate are made.
	 */
	size_t availableBytesOut;

	// Total number of bytes written to the output so far, through all calls to inflate()/deflate().
	ulong totalBytesOut;

	// The compression level to use in this codec. Useful only in compression mode.
	CompressionLevel compressLevel = CompressionLevel.defaultLevel;

	/**
	 * The compression strategy to use.
	 * This is only effective in compression. The theory offered by ZLIB is that different
	 * strategies could potentially produce significant differences in compression behavior
	 * for different data sets. Unfortunately I don't have any good recommendations for how
	 * to set it differently. When I tested changing the strategy I got minimally different
	 * compression performance. It's best to leave this property alone if you don't have a
	 * good feel for it. Or, you may want to produce a test harness that runs through the
	 * different strategy options and evaluates them on different file types. If you do that,
	 * let me know your results.
	 */
	CompressionStrategy compressStrategy = CompressionStrategy.defaultStrategy;

	int compressMemLevel = ZipConst.deflateMemLevelDefault;

	/**
	 * The number of Window Bits to use.
	 * This gauges the size of the sliding window, and hence the
	 * compression effectiveness as well as memory consumption. It's best to just leave this
	 * setting alone if you don't know what it is. The maximum value is 15 bits, which implies
	 * a 32k window.
	 */
	int windowBits = ZipConst.windowBitsDefault;

	bool rfc1950Header = true;

	// The Adler32 checksum on the data transferred through the codec so far. You probably don't need to look at this.
	@property final uint adler32() const
    {
        return _adler32;
    }

	// used for diagnostics, when something goes wrong!
	@property final int errorCode() const
    {
		return _errorCode;
    }

	// used for diagnostics, when something goes wrong!
	@property final string errorMessage() const
    {
		return _errorMessage;
    }

private:
	DeflateManager dstate;
	InflateManager istate;
	string _errorMessage;
	uint _adler32;
	int _errorCode;
}


// Any below codes are private
private:

unittest // Inflate
{
	import pham.utl.object : bytesFromHexs;
    import pham.utl.test;
    traceUnitTest!("pham.utl.zip")("unittest pham.utl.zip.ZlibCodec.Inflate");

	auto zipData1 = bytesFromHexs("789C626060E0644005820C9CC195B9B9A9254599C98C2C8E45C926107146980200000000FFFF");
	auto expectUnzipData1 = bytesFromHexs("0000000900000000000000000000000000000011000953796D6D6574726963010441726334000000000000010000000000000000");

	auto zipper = new ZlibCodec(CompressionMode.decompress);
	zipper.resetBuffers(zipData1, 256_000);
	auto r = zipper.inflate(FlushType.none);
	assert(r == ZipResult.Z_OK);
	assert(zipper.availableBytesIn == 0);
	assert(zipper.nextOut != 0);
	assert(zipper.adler32 == 2103313713);
	assert(zipper.peekOutput() == expectUnzipData1);

	auto zipData2 = bytesFromHexs("62C0D483220F000000FFFF");
	auto expectUnzipData2 = bytesFromHexs("0000000900000000000000000000000000000000000000010000000000000000");
	zipper.resetBuffers(zipData2, 256_000);
	r = zipper.inflate(FlushType.none);
	assert(r == ZipResult.Z_OK);
	assert(zipper.availableBytesIn == 0);
	assert(zipper.nextOut != 0);
	assert(zipper.adler32 == 614139195);
	assert(zipper.peekOutput() == expectUnzipData2);
}

unittest // Deflate
{
	import pham.utl.object : bytesFromHexs;
    import pham.utl.test;
    traceUnitTest!("pham.utl.zip")("unittest pham.utl.zip.ZlibCodec.Deflate");

	auto zipData1 = bytesFromHexs("789C626060E0644005820C9CC195B9B9A9254599C98C2C8E45C926107146980200000000FFFF");
	auto expectUnzipData1 = bytesFromHexs("0000000900000000000000000000000000000011000953796D6D6574726963010441726334000000000000010000000000000000");

	auto zipper = new ZlibCodec(CompressionMode.compress);
	zipper.resetBuffers(expectUnzipData1, 256_000);
	auto r = zipper.deflate(FlushType.sync);
	assert(r == ZipResult.Z_OK);
	assert(zipper.availableBytesIn == 0);
	assert(zipper.nextOut != 0);
	assert(zipper.adler32 == 2103313713);
	assert(zipper.peekOutput() == zipData1);

	auto zipData2 = bytesFromHexs("62C0D483220F000000FFFF");
	auto expectUnzipData2 = bytesFromHexs("0000000900000000000000000000000000000000000000010000000000000000");
	zipper.resetBuffers(expectUnzipData2, 256_000);
	r = zipper.deflate(FlushType.sync);
	assert(r == ZipResult.Z_OK);
	assert(zipper.availableBytesIn == 0);
	assert(zipper.nextOut != 0);
	assert(zipper.adler32 == 614139195);
	assert(zipper.peekOutput() == zipData2);
}

unittest // Deflate & Inflate long string
{
	import pham.cp.random : CipherRandomGenerator;
	import pham.utl.array : ShortStringBuffer;
    import pham.utl.test;
    traceUnitTest!("pham.utl.zip")("unittest pham.utl.zip.ZlibCodec.Deflate & Inflate long string");

	CipherRandomGenerator generator;
	ShortStringBuffer!ubyte buffer;
	auto sourceBytes = generator.nextBytes(buffer, 256_000)[].dup;

	auto zipper = new ZlibCodec(CompressionMode.compress);
	zipper.resetBuffers(sourceBytes[], 1024 * 1024);
	auto r = zipper.deflate(FlushType.sync);
	assert(r == ZipResult.Z_OK);
	assert(zipper.availableBytesIn == 0);
	assert(zipper.nextOut != 0);
	auto zipData = zipper.peekOutput().dup;

	auto zipper2 = new ZlibCodec(CompressionMode.decompress);
	zipper2.resetBuffers(zipData, 1024 * 1024);
	r = zipper2.inflate(FlushType.none);
	assert(r == ZipResult.Z_OK);
	assert(zipper2.availableBytesIn == 0);
	assert(zipper2.nextOut != 0);
	assert(zipper2.peekOutput() == sourceBytes[]);
}

version (UnitTestZLib)
unittest // ZlibCodec.Deflate
{
    import pham.utl.test;
    traceUnitTest!("pham.utl.zip")("unittest pham.utl.zip.ZlibCodec.Deflate.BigFile");

	auto bigData = dgReadAllBinary("zip_test_expressionsem.d");
	auto expectZipBigData = dgReadAllBinary("zip_test_expressionsem.zip");

	auto zipper = new ZlibCodec(CompressionMode.compress);
	zipper.resetBuffers(bigData, 1024 * 1024);
	auto r = zipper.deflate(FlushType.sync);
	assert(r == ZipResult.Z_OK);
	assert(zipper.availableBytesIn == 0);
	assert(zipper.nextOut != 0);
	assert(zipper.adler32 == 460_074_401);
	auto zipData = zipper.peekOutput().dup;
	assert(zipData == expectZipBigData);

	auto zipper2 = new ZlibCodec(CompressionMode.decompress);
	zipper2.resetBuffers(zipData, 1024 * 1024);
	r = zipper2.inflate(FlushType.none);
	assert(r == ZipResult.Z_OK);
	assert(zipper2.availableBytesIn == 0);
	assert(zipper2.nextOut != 0);
	assert(zipper2.adler32 == 460_074_401);
	assert(zipper2.peekOutput() == bigData);
}
