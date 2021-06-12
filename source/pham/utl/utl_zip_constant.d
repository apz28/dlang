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

module pham.utl.zip_constant;

nothrow @safe:

enum ZipConst
{
    // The maximum number of window bits for the Deflate algorithm.
    windowBitsMin = 9,

    // 32K LZ77 window
    windowBitsMax = 15,

    // The default number of window bits for the Deflate algorithm.
    windowBitsDefault = windowBitsMax,

    /**
     * The minimum size of the working buffer used in the ZlibCodec class.
     * Currently it is 128 bytes.
     */
    workingBufferSizeMin = 1_024,

    /**
     * The size of the working buffer used in the ZlibCodec class.
     * Defaults to 16_384 bytes.
     */
    workingBufferSizeDefault = 16_384,

	deflateMemLevelMax = 9,
    deflateMemLevelMin = 1,
    deflateMemLevelDefault = 8,

    MAX_BITS     = 15,
    BL_CODES     = 19,
    D_CODES      = 30,
    LITERALS     = 256,
    LENGTH_CODES = 29,
    L_CODES      = LITERALS + 1 + LENGTH_CODES,

    // Bit length codes must not exceed MAX_BL_BITS bits
    MAX_BL_BITS  = 7,

    // repeat previous bit length 3-6 times (2 bits of repeat count)
    REP_3_6      = 16,

    // repeat a zero length 3-10 times (3 bits of repeat count)
    REPZ_3_10    = 17,

    // repeat a zero length 11-138 times (7 bits of repeat count)
    REPZ_11_138  = 18,
}

/**
 * Describes how to flush the current deflate operation.
 * The different FlushType values are useful when using a Deflate in a streaming application.
 */
enum FlushType
{
    // No flush at all.
    none = 0,

    /**
     * Closes the current block, but doesn't flush it to
     * the output. Used internally only in hypothetical scenarios.
     * This was supposed to be removed by Zlib, but it is
     * still in use in some edge cases.
     */
    partial,

    /**
     * Use this during compression to specify that all pending output should be
     * flushed to the output buffer and the output should be aligned on a byte
     * boundary. You might use this in a streaming communication scenario, so that
     * the decompressor can get all input data available so far. When using this
     * with a ZlibCodec, availableBytesIn will be zero after the call if
     * enough output space has been provided before the call. Flushing will
     * degrade compression and so it should be used only when necessary.
     */
    sync,

    /**
     * Use this during compression to specify that all output should be flushed, as
     * with FlushType.sync, but also, the compression state should be reset
     * so that decompression can restart from this point if previous compressed
     * data has been damaged or if random access is desired. Using
     * FlushType.full too often can significantly degrade the compression.
     */
    full,

    // Signals the end of the compression/decompression stream.
    finish,
}

// The compression level to be used when using a DeflateStream or ZlibStream with CompressionMode.compress.
enum CompressionLevel
{
    /**
     * None means that the data will be simply stored, with no change at all.
     * If you are producing ZIPs for use on Mac OSX, be aware that archives produced with CompressionLevel.none
     * cannot be opened with the default zip reader. Use a different CompressionLevel.
     */
    none = 0,

    // Same as none.
    level0 = 0,

    // The fastest but least effective compression.
    level1 = 1,

    // A little slower, but better, than level 1.
    level2 = 2,

    // A little slower, but better, than level 2.
    level3 = 3,

    // A little slower, but better, than level 3.
    level4 = 4,

    // A little slower than level 4, but with better compression.
    level5 = 5,

    // The default compression level, with a good balance of speed and compression efficiency.
    level6 = 6,

    // Pretty good compression!
    level7 = 7,

    //  Better compression than level7.
    level8 = 8,

    /**
     * The best compression, where best means greatest reduction in size of the input data stream.
     * This is also the slowest compression.
     */
    level9 = 9,

    // A synonym for level6.
    defaultLevel = level6,

    // A synonym for level1.
    bestSpeed = level1,

    // A synonym for level9.
    bestCompression = 9,
}

/**
 * Describes options for how the compression algorithm is executed. Different strategies
 * work better on different sorts of data. The strategy parameter can affect the compression
 * ratio and the speed of compression but not the correctness of the compresssion.
 */
enum CompressionStrategy
{
    // The default strategy is probably the best for normal data.
    defaultStrategy = 0,

    /**
     * The filtered strategy is intended to be used most effectively with data produced by a
     * filter or predictor. By this definition, filtered data consists mostly of small
     * values with a somewhat random distribution. In this case, the compression algorithm
     * is tuned to compress them better. The effect of filtered is to force more Huffman
     * coding and less string matching; it is a half-step between defaultStrategy and huffmanOnly.
     */
    filtered = 1,

    /**
     * Using huffmanOnly will force the compressor to do Huffman encoding only, with no
     * string matching.
     */
    huffmanOnly = 2,
}

// An enum to specify the direction of transcoding - whether to compress or decompress.
enum CompressionMode
{
    /// Used to specify that the stream should compress the data.
    compress,

    /// Used to specify that the stream should decompress the data.
    decompress,
}

enum DeflateFlavor
{
	store,
	fast,
	slow
}

enum ZipResult
{
    // indicates everything is A-OK
    Z_OK = 0,

    // Indicates that the last operation reached the end of the stream.
    Z_STREAM_END = 1,

    // The operation ended in need of a dictionary.
    Z_NEED_DICT = 2,

    Z_ERRNO = -1,

    // There was an error with the stream - not enough data, not open and readable, etc.
    Z_STREAM_ERROR = -2,

    // There was an error with the data - not enough data, bad data, etc.
    Z_DATA_ERROR = -3,

    Z_MEM_ERROR = -4,

    // There was an error with the working buffer.
    Z_BUF_ERROR = -5,

    Z_VERSION_ERROR = -6,
}

/**
 * Computes an Adler-32 checksum.
 * The Adler checksum is similar to a CRC checksum, but faster to compute, though less
 * reliable. It is used in producing RFC1950 compressed streams. The Adler checksum
 * is a required part of the "ZLIB" standard. Applications will almost never need to
 * use this class directly.
 */
struct Adler
{
nothrow @safe:

public:
    /**
     * Calculates the Adler32 checksum.
     * This is used within ZLIB. You probably don't need to use this directly.
     * Example:
     *  To compute an Adler32 checksum on a ubyte array, buffer:
     *  ```
     *      uint adler = Adler.adler32(Adler.adler32(0, null), buffer);
     *  ```
     */
    static uint adler32(uint adler, scope const(ubyte)[] buf) pure
    {
        if (buf == null)
            return 1;

        uint s1 = cast(uint)(adler & 0xffff);
        uint s2 = cast(uint)((adler >> 16) & 0xffff);
        size_t index = 0;
        auto len = buf.length;
        while (len > 0)
        {
            auto k = len < nMax ? len : nMax;
            len -= k;
            while (k >= 16)
            {
                //s1 += (buf[index++] & 0xff); s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                s1 += buf[index++]; s2 += s1;
                k -= 16;
            }

            if (k != 0)
            {
                do
                {
                    s1 += buf[index++];
                    s2 += s1;
                }
                while (--k != 0);
            }
            s1 %= base;
            s2 %= base;
        }
        return cast(uint)((s2 << 16) | s1);
    }

private:
    // largest prime smaller than 65_536
    enum uint base = 65_521;

    // nMax is the largest n such that 255n(n+1)/2 + (n+1)(base-1) <= 2^32-1
    enum uint nMax = 5_552;
}
