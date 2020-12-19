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

module pham.utl.zip_inflate;

import std.exception : assumeWontThrow;
import std.format : format;

import pham.utl.zip_constant;
import pham.utl.zip_tree;
import pham.utl.zip;

nothrow @safe:

class InflateManager
{
nothrow @safe:

public:
	this(ZlibCodec codec)
    {
		this._codec = codec;
    }

	final int initialize(int windowBits, bool expectRfc1950HeaderBytes)
    in
    {
		assert(ZipConst.windowBitsMin <= windowBits && windowBits <= ZipConst.windowBitsMax);
    }
	do
	{
		this.wbits = windowBits;
		this.handleRfc1950HeaderBytes = expectRfc1950HeaderBytes;
		this.blocks = null; // Need to create new blocks

		// handle undocumented nowrap option (no zlib header or check)
		//nowrap = 0;
		//if (w < 0)
		//{
		//    w = - w;
		//    nowrap = 1;
		//}

		// reset state
		reset();
		return ZipResult.Z_OK;
	}

	final int end()
	{
		if (blocks !is null)
        {
			blocks.free();
			blocks = null;
        }
		return ZipResult.Z_OK;
	}

	final int inflate(FlushType flush)
	in
    {
		assert(_codec.inputBuffer !is null);
    }
	do
	{
		int b;

		//int f = (flush == FlushType.Finish) ? ZipResult.Z_BUF_ERROR : ZipResult.Z_OK;

		// workitem 8870
		int f = ZipResult.Z_OK;
		int r = ZipResult.Z_BUF_ERROR;

		while (true)
		{
			final switch (mode)
			{
				case InflateManagerMode.METHOD:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
					_codec.totalBytesIn++;
					if (((method = _codec.inputBuffer[_codec.nextIn++]) & 0xf) != Z_DEFLATED)
					{
						mode = InflateManagerMode.BAD;
						marker = 5; // can't try inflateSync
						_codec.setError(ZipResult.Z_ERRNO, assumeWontThrow(format("unknown compression method (%d)", method)));
						break;
					}
					if ((method >> 4) + 8 > wbits)
					{
						mode = InflateManagerMode.BAD;
						marker = 5; // can't try inflateSync
						_codec.setError(ZipResult.Z_ERRNO, assumeWontThrow(format("invalid window size (%d)", (method >> 4) + 8)));
						break;
					}
					mode = InflateManagerMode.FLAG;
					break;

				case InflateManagerMode.FLAG:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
					_codec.totalBytesIn++;
					b = (_codec.inputBuffer[_codec.nextIn++]) & 0xff;

					if ((((method << 8) + b) % 31) != 0)
					{
						mode = InflateManagerMode.BAD;
						_codec.setError(ZipResult.Z_DATA_ERROR, "incorrect header check");
						marker = 5; // can't try inflateSync
						break;
					}

					mode = ((b & PRESET_DICT) == 0)
						? InflateManagerMode.BLOCKS
						: InflateManagerMode.DICT4;
					break;

				case InflateManagerMode.DICT4:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
					_codec.totalBytesIn++;
					expectedCheck = cast(uint)((_codec.inputBuffer[_codec.nextIn++] << 24) & 0xff000000);
					mode = InflateManagerMode.DICT3;
					break;

				case InflateManagerMode.DICT3:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
					_codec.totalBytesIn++;
					expectedCheck += cast(uint)((_codec.inputBuffer[_codec.nextIn++] << 16) & 0x00ff0000);
					mode = InflateManagerMode.DICT2;
					break;

				case InflateManagerMode.DICT2:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
					_codec.totalBytesIn++;
					expectedCheck += cast(uint)((_codec.inputBuffer[_codec.nextIn++] << 8) & 0x0000ff00);
					mode = InflateManagerMode.DICT1;
					break;

				case InflateManagerMode.DICT1:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
                    _codec.totalBytesIn++;
					expectedCheck += cast(uint)(_codec.inputBuffer[_codec.nextIn++] & 0x000000ff);
					_codec.resetAdler32(expectedCheck);
					mode = InflateManagerMode.DICT0;
					return ZipResult.Z_NEED_DICT;

				case InflateManagerMode.DICT0:
					mode = InflateManagerMode.BAD;
					marker = 0; // can try inflateSync
					return _codec.setError(ZipResult.Z_NEED_DICT, "need dictionary");

				case InflateManagerMode.BLOCKS:
					r = blocks.process(r);
					if (r == ZipResult.Z_DATA_ERROR)
					{
						mode = InflateManagerMode.BAD;
						marker = 0; // can try inflateSync
						break;
					}

					if (r == ZipResult.Z_OK)
                        r = f;

					if (r != ZipResult.Z_STREAM_END)
						return r;

					r = f;
					computedCheck = blocks.reset();
					if (!handleRfc1950HeaderBytes)
					{
						mode = InflateManagerMode.DONE;
						return ZipResult.Z_STREAM_END;
					}
					mode = InflateManagerMode.CHECK4;
					break;

				case InflateManagerMode.CHECK4:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
					_codec.totalBytesIn++;
					expectedCheck = cast(uint)((_codec.inputBuffer[_codec.nextIn++] << 24) & 0xff000000);
					mode = InflateManagerMode.CHECK3;
					break;

				case InflateManagerMode.CHECK3:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
                    _codec.totalBytesIn++;
					expectedCheck += cast(uint)((_codec.inputBuffer[_codec.nextIn++] << 16) & 0x00ff0000);
					mode = InflateManagerMode.CHECK2;
					break;

				case InflateManagerMode.CHECK2:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
					_codec.totalBytesIn++;
					expectedCheck += cast(uint)((_codec.inputBuffer[_codec.nextIn++] << 8) & 0x0000ff00);
					mode = InflateManagerMode.CHECK1;
					break;

				case InflateManagerMode.CHECK1:
					if (_codec.availableBytesIn == 0)
                        return r;
					r = f;
					_codec.availableBytesIn--;
                    _codec.totalBytesIn++;
					expectedCheck += cast(uint)(_codec.inputBuffer[_codec.nextIn++] & 0x000000ff);
					if (computedCheck != expectedCheck)
					{
						mode = InflateManagerMode.BAD;
						marker = 5; // can't try inflateSync
						_codec.setError(ZipResult.Z_DATA_ERROR, assumeWontThrow(format("incorrect data check %lu / %lu", computedCheck, expectedCheck)));
						break;
					}
					mode = InflateManagerMode.DONE;
					return ZipResult.Z_STREAM_END;

				case InflateManagerMode.DONE:
					return ZipResult.Z_STREAM_END;

				case InflateManagerMode.BAD:
					return _codec.setError(ZipResult.Z_ERRNO, "Bad state.\n" ~ _codec.errorMessage);

                version (none) // todo remove
                {
                default:
					return _codec.setError(ZipResult.Z_STREAM_ERROR, "Stream error.");
                }
			}
		}
	}

	final typeof(this) reset()
	{
		_codec.totalBytesIn = _codec.totalBytesOut = 0;
		_codec.setError(ZipResult.Z_OK, null);
		mode = handleRfc1950HeaderBytes ? InflateManagerMode.METHOD : InflateManagerMode.BLOCKS;
		if (blocks is null)
			blocks = new InflateBlocks(_codec, handleRfc1950HeaderBytes ? this : null, 1 << wbits);
		else
			blocks.reset();
		return this;
	}

	final int setDictionary(scope const(ubyte)[] dictionary)
	{
		if (mode != InflateManagerMode.DICT0)
			return _codec.setError(ZipResult.Z_STREAM_ERROR, "Stream error");

		size_t index = 0;
		size_t length = dictionary.length;

		if (Adler.adler32(1, dictionary) != _codec.adler32)
			return ZipResult.Z_DATA_ERROR;

		_codec.resetAdler32(0, null);

		if (length >= (1 << wbits))
		{
			length = (1 << wbits) - 1;
			index = dictionary.length - length;
		}
		blocks.setDictionary(dictionary[index..index + length]);
		mode = InflateManagerMode.BLOCKS;
		return ZipResult.Z_OK;
	}

	final int sync()
	{
		size_t n; // number of bytes to look at
		size_t p; // pointer to bytes
		int m; // number of marker bytes found in a row
		long r, w; // temporaries to save total_in and total_out

		// set up
		if (mode != InflateManagerMode.BAD)
		{
			mode = InflateManagerMode.BAD;
			marker = 0;
		}
		if ((n = _codec.availableBytesIn) == 0)
			return ZipResult.Z_BUF_ERROR;
		p = _codec.nextIn;
		m = marker;

		// search
		while (n != 0 && m < 4)
		{
			if (_codec.inputBuffer[p] == mark[m])
				m++;
			else if (_codec.inputBuffer[p] != 0)
				m = 0;
			else
				m = 4 - m;
			p++;
            n--;
		}

		// restore
		_codec.totalBytesIn += p - _codec.nextIn;
		_codec.nextIn = p;
		_codec.availableBytesIn = n;
		marker = m;

		// return no joy or set up to restart on a new block
		if (m != 4)
			return ZipResult.Z_DATA_ERROR;
		r = _codec.totalBytesIn;
		w = _codec.totalBytesOut;
		reset();
		_codec.totalBytesIn = r;
		_codec.totalBytesOut = w;
		mode = InflateManagerMode.BLOCKS;
		return ZipResult.Z_OK;
	}

	/**
	 * Returns true if inflate is currently at the end of a block generated
	 * by Z_SYNC_FLUSH or Z_FULL_FLUSH. This function is used by one PPP
	 * implementation to provide an additional safety check. PPP uses Z_SYNC_FLUSH
	 * but removes the length bytes of the resulting empty stored block. When
	 * decompressing, PPP checks that at the end of input packet, inflate is
	 * waiting for these length bytes.
	 */
	final int syncPoint()
	{
		return blocks.syncPoint();
	}

public:
	bool handleRfc1950HeaderBytes = true;

private:
	enum const(ubyte)[] mark = [0, 0, 0xff, 0xff];

	// preset dictionary flag in zlib header
	enum int PRESET_DICT = 0x20;

	enum int Z_DEFLATED = 8;

	enum InflateManagerMode : byte
	{
		METHOD = 0,  // waiting for method byte
		FLAG = 1,  // waiting for flag byte
		DICT4 = 2,  // four dictionary check bytes to go
		DICT3 = 3,  // three dictionary check bytes to go
		DICT2 = 4,  // two dictionary check bytes to go
		DICT1 = 5,  // one dictionary check byte to go
		DICT0 = 6,  // waiting for inflateSetDictionary
		BLOCKS = 7,  // decompressing blocks
		CHECK4 = 8,  // four check bytes to go
		CHECK3 = 9,  // three check bytes to go
		CHECK2 = 10, // two check bytes to go
		CHECK1 = 11, // one check byte to go
		DONE = 12, // finished check, done
		BAD = 13, // got an error--stay here
	}

	InflateManagerMode mode; // current inflate mode
	ZlibCodec _codec; // pointer back to this zlib stream

	// mode dependent information
	int method; // if FLAGS, method byte

	// if CHECK, check values to compare
	uint computedCheck; // computed check value
	uint expectedCheck; // stream check value

	// if BAD, inflateSync's marker bytes count
	int marker;

	// mode independent information
	//internal int nowrap; // flag for no wrapper
	int wbits; // log2(window size)  (8..15, defaults to 15)

	InflateBlocks blocks; // current inflate_blocks state
}

// And'ing with mask[n] masks the lower n bits
private enum int[] InflateMask = [
	0x00000000, 0x00000001, 0x00000003, 0x00000007,
	0x0000000f, 0x0000001f, 0x0000003f, 0x0000007f,
	0x000000ff, 0x000001ff, 0x000003ff, 0x000007ff,
	0x00000fff, 0x00001fff, 0x00003fff, 0x00007fff, 0x0000ffff
];

private class InflateBlocks
{
nothrow @safe:

public:
	this(ZlibCodec codec, Object checkfn, int w)
	{
		this._codec = codec;
		this.checkfn = checkfn;
		this.end = w;

		this.bb.length = 1;
		this.tb.length = 1;
		this.hufts.length = MANY * 3;
		this.window.length = w;
		this.mode = InflateBlockMode.TYPE;
		this.codes = new InflateCodes();
		this.inftree = new InfTree();

		reset();
	}

	final uint reset()
	{
		const oldCheck = check;

		mode = InflateBlockMode.TYPE;
		bitk = 0;
		bitb = 0;
		readAt = writeAt = 0;

		if (checkfn !is null)
			check = _codec.resetAdler32(0, null);

		return oldCheck;
	}

	final int process(int r)
	{
		int t; // temporary storage
		int b; // bit buffer
		int k; // bits in bit buffer
		size_t p; // input data pointer
		size_t n; // bytes available there
		int q; // output window write pointer
		int m; // bytes to end of window or read pointer

		// copy input/output information to locals (UPDATE macro restores)

		p = _codec.nextIn;
		n = _codec.availableBytesIn;
		b = bitb;
		k = bitk;

		q = writeAt;
		m = cast(int)(q < readAt ? readAt - q - 1 : end - q);

		// process input based on current state
		while (true)
		{
			final switch (mode)
			{
				case InflateBlockMode.TYPE:
					while (k < 3)
					{
						if (n != 0)
						{
							r = ZipResult.Z_OK;
						}
						else
						{
							bitb = b;
                            bitk = k;
							_codec.availableBytesIn = n;
							_codec.totalBytesIn += p - _codec.nextIn;
							_codec.nextIn = p;
							writeAt = q;
							return flush(r);
						}

						n--;
						b |= (_codec.inputBuffer[p++] & 0xff) << k;
						k += 8;
					}
					t = cast(int)(b & 7);
					last = t & 1;

					switch (cast(uint)t >> 1)
					{
						case 0:  // stored
							b >>= 3;
                            k -= 3;
							t = k & 7; // go to byte boundary
							b >>= t;
                            k -= t;
							mode = InflateBlockMode.LENS; // get length of stored block
							break;

						case 1:  // fixed
							int[] bl = new int[](1);
							int[] bd = new int[](1);
							int[][] tl = new int[][](1, 0);
							int[][] td = new int[][](1, 0);
							InfTree.inflateTreesFixed(bl, bd, tl, td, _codec);
							codes.init(bl[0], bd[0], tl[0], 0, td[0], 0);
							b >>= 3;
                            k -= 3;
							mode = InflateBlockMode.CODES;
							break;

						case 2:  // dynamic
							b >>= 3;
                            k -= 3;
							mode = InflateBlockMode.TABLE;
							break;

						case 3:  // illegal
							b >>= 3;
                            k -= 3;
							mode = InflateBlockMode.BAD;
							r = _codec.setError(ZipResult.Z_DATA_ERROR, "invalid block type");
							bitb = b;
                            bitk = k;
							_codec.availableBytesIn = n;
							_codec.totalBytesIn += p - _codec.nextIn;
							_codec.nextIn = p;
							writeAt = q;
							return flush(r);

						default:
							break;
					}
					break;

				case InflateBlockMode.LENS:
					while (k < (32))
					{
						if (n != 0)
						{
							r = ZipResult.Z_OK;
						}
						else
						{
							bitb = b;
                            bitk = k;
							_codec.availableBytesIn = n;
							_codec.totalBytesIn += p - _codec.nextIn;
							_codec.nextIn = p;
							writeAt = q;
							return flush(r);
						}

						n--;
						b |= (_codec.inputBuffer[p++] & 0xff) << k;
						k += 8;
					}

					if ((((~b) >> 16) & 0xffff) != (b & 0xffff))
					{
						mode = InflateBlockMode.BAD;
						r = _codec.setError(ZipResult.Z_DATA_ERROR, "invalid stored block lengths");
						bitb = b;
                        bitk = k;
						_codec.availableBytesIn = n;
						_codec.totalBytesIn += p - _codec.nextIn;
						_codec.nextIn = p;
						writeAt = q;
						return flush(r);
					}
					left = (b & 0xffff);
					b = k = 0; // dump bits
					mode = left != 0 ? InflateBlockMode.STORED : (last != 0 ? InflateBlockMode.DRY : InflateBlockMode.TYPE);
					break;

				case InflateBlockMode.STORED:
					if (n == 0)
					{
						bitb = b;
                        bitk = k;
						_codec.availableBytesIn = n;
						_codec.totalBytesIn += p - _codec.nextIn;
						_codec.nextIn = p;
						writeAt = q;
						return flush(r);
					}

					if (m == 0)
					{
						if (q == end && readAt != 0)
						{
							q = 0;
                            m = cast(int)(q < readAt ? readAt - q - 1 : end - q);
						}
						if (m == 0)
						{
							writeAt = q;
							r = flush(r);
							q = writeAt;
                            m = cast(int)(q < readAt ? readAt - q - 1 : end - q);
							if (q == end && readAt != 0)
							{
								q = 0;
                                m = cast(int)(q < readAt ? readAt - q - 1 : end - q);
							}
							if (m == 0)
							{
								bitb = b;
                                bitk = k;
								_codec.availableBytesIn = n;
								_codec.totalBytesIn += p - _codec.nextIn;
								_codec.nextIn = p;
								writeAt = q;
								return flush(r);
							}
						}
					}
					r = ZipResult.Z_OK;

					t = left;
					if (t > n)
						t = cast(int)n;
					if (t > m)
						t = m;
					window[q..q + t] = _codec.inputBuffer[p..p + t];
					p += t; n -= t;
					q += t; m -= t;
					if ((left -= t) != 0)
						break;
					mode = last != 0 ? InflateBlockMode.DRY : InflateBlockMode.TYPE;
					break;

				case InflateBlockMode.TABLE:
					while (k < (14))
					{
						if (n != 0)
						{
							r = ZipResult.Z_OK;
						}
						else
						{
							bitb = b;
                            bitk = k;
							_codec.availableBytesIn = n;
							_codec.totalBytesIn += p - _codec.nextIn;
							_codec.nextIn = p;
							writeAt = q;
							return flush(r);
						}

						n--;
						b |= (_codec.inputBuffer[p++] & 0xff) << k;
						k += 8;
					}

					table = t = (b & 0x3fff);
					if ((t & 0x1f) > 29 || ((t >> 5) & 0x1f) > 29)
					{
						mode = InflateBlockMode.BAD;
						r = _codec.setError(ZipResult.Z_DATA_ERROR, "too many length or distance symbols");
						bitb = b;
                        bitk = k;
						_codec.availableBytesIn = n;
						_codec.totalBytesIn += p - _codec.nextIn;
						_codec.nextIn = p;
						writeAt = q;
						return flush(r);
					}
					t = 258 + (t & 0x1f) + ((t >> 5) & 0x1f);
					if (blens.length < t)
						blens.length = t;
					blens[] = 0;

					b >>= 14;
					k -= 14;

					index = 0;
					mode = InflateBlockMode.BTREE;
					goto case InflateBlockMode.BTREE;

				case InflateBlockMode.BTREE:
					while (index < 4 + (table >> 10))
					{
						while (k < 3)
						{
							if (n != 0)
							{
								r = ZipResult.Z_OK;
							}
							else
							{
								bitb = b;
                                bitk = k;
								_codec.availableBytesIn = n;
								_codec.totalBytesIn += p - _codec.nextIn;
								_codec.nextIn = p;
								writeAt = q;
								return flush(r);
							}

							n--;
							b |= (_codec.inputBuffer[p++] & 0xff) << k;
							k += 8;
						}

						blens[border[index++]] = b & 7;

						b >>= 3;
                        k -= 3;
					}

					while (index < 19)
					{
						blens[border[index++]] = 0;
					}

					bb[0] = 7;
					t = inftree.inflateTreesBits(blens, bb, tb, hufts, _codec);
					if (t != ZipResult.Z_OK)
					{
						r = t;
						if (r == ZipResult.Z_DATA_ERROR)
						{
							blens = null;
							mode = InflateBlockMode.BAD;
						}

						bitb = b;
                        bitk = k;
						_codec.availableBytesIn = n;
						_codec.totalBytesIn += p - _codec.nextIn;
						_codec.nextIn = p;
						writeAt = q;
						return flush(r);
					}

					index = 0;
					mode = InflateBlockMode.DTREE;
					goto case InflateBlockMode.DTREE;

				case InflateBlockMode.DTREE:
					while (true)
					{
						t = table;
						if (!(index < 258 + (t & 0x1f) + ((t >> 5) & 0x1f)))
						{
							break;
						}

						int i, j, c;

						t = bb[0];

						while (k < t)
						{
							if (n != 0)
							{
								r = ZipResult.Z_OK;
							}
							else
							{
								bitb = b;
                                bitk = k;
								_codec.availableBytesIn = n;
								_codec.totalBytesIn += p - _codec.nextIn;
								_codec.nextIn = p;
								writeAt = q;
								return flush(r);
							}

							n--;
							b |= (_codec.inputBuffer[p++] & 0xff) << k;
							k += 8;
						}

						t = hufts[(tb[0] + (b & InflateMask[t])) * 3 + 1];
						c = hufts[(tb[0] + (b & InflateMask[t])) * 3 + 2];

						if (c < 16)
						{
							b >>= t; k -= t;
							blens[index++] = c;
						}
						else
						{
							// c == 16..18
							i = c == 18 ? 7 : c - 14;
							j = c == 18 ? 11 : 3;

							while (k < (t + i))
							{
								if (n != 0)
								{
									r = ZipResult.Z_OK;
								}
								else
								{
									bitb = b;
                                    bitk = k;
									_codec.availableBytesIn = n;
									_codec.totalBytesIn += p - _codec.nextIn;
									_codec.nextIn = p;
									writeAt = q;
									return flush(r);
								}

								n--;
								b |= (_codec.inputBuffer[p++] & 0xff) << k;
								k += 8;
							}

							b >>= t;
                            k -= t;

							j += (b & InflateMask[i]);

							b >>= i;
                            k -= i;

							i = index;
							t = table;
							if (i + j > 258 + (t & 0x1f) + ((t >> 5) & 0x1f) || (c == 16 && i < 1))
							{
								blens = null;
								mode = InflateBlockMode.BAD;
								r = _codec.setError(ZipResult.Z_DATA_ERROR, "invalid bit length repeat");
								bitb = b;
                                bitk = k;
								_codec.availableBytesIn = n;
								_codec.totalBytesIn += p - _codec.nextIn;
								_codec.nextIn = p;
								writeAt = q;
								return flush(r);
							}

							c = (c == 16) ? blens[i - 1] : 0;
							do
							{
								blens[i++] = c;
							}
							while (--j != 0);
							index = i;
						}
					}

					tb[0] = -1;
					{
						int[] bl = [9];  // must be <= 9 for lookahead assumptions
						int[] bd = [6]; // must be <= 9 for lookahead assumptions
						int[] tl = new int[1];
						int[] td = new int[1];

						t = table;
						t = inftree.inflateTreesDynamic(257 + (t & 0x1f), 1 + ((t >> 5) & 0x1f), blens, bl, bd, tl, td, hufts, _codec);

						if (t != ZipResult.Z_OK)
						{
							if (t == ZipResult.Z_DATA_ERROR)
							{
								blens = null;
								mode = InflateBlockMode.BAD;
							}
							r = t;

							bitb = b;
                            bitk = k;
							_codec.availableBytesIn = n;
							_codec.totalBytesIn += p - _codec.nextIn;
							_codec.nextIn = p;
							writeAt = q;
							return flush(r);
						}
						codes.init(bl[0], bd[0], hufts, tl[0], hufts, td[0]);
					}
					mode = InflateBlockMode.CODES;
					goto case InflateBlockMode.CODES;

				case InflateBlockMode.CODES:
					bitb = b;
                    bitk = k;
					_codec.availableBytesIn = n;
					_codec.totalBytesIn += p - _codec.nextIn;
					_codec.nextIn = p;
					writeAt = q;

					r = codes.process(this, r);
					if (r != ZipResult.Z_STREAM_END)
					{
						return flush(r);
					}

					r = ZipResult.Z_OK;
					p = _codec.nextIn;
					n = _codec.availableBytesIn;
					b = bitb;
					k = bitk;
					q = writeAt;
					m = cast(int)(q < readAt ? readAt - q - 1 : end - q);

					if (last == 0)
					{
						mode = InflateBlockMode.TYPE;
						break;
					}
					mode = InflateBlockMode.DRY;
					goto case InflateBlockMode.DRY;

				case InflateBlockMode.DRY:
					writeAt = q;
					r = flush(r);
					q = writeAt;
                    m = cast(int)(q < readAt ? readAt - q - 1 : end - q);
					if (readAt != writeAt)
					{
						bitb = b;
                        bitk = k;
						_codec.availableBytesIn = n;
						_codec.totalBytesIn += p - _codec.nextIn;
						_codec.nextIn = p;
						writeAt = q;
						return flush(r);
					}
					mode = InflateBlockMode.DONE;
					goto case InflateBlockMode.DONE;

				case InflateBlockMode.DONE:
					r = ZipResult.Z_STREAM_END;
					bitb = b;
					bitk = k;
					_codec.availableBytesIn = n;
					_codec.totalBytesIn += p - _codec.nextIn;
					_codec.nextIn = p;
					writeAt = q;
					return flush(r);

				case InflateBlockMode.BAD:
					r = ZipResult.Z_DATA_ERROR;

					bitb = b;
                    bitk = k;
					_codec.availableBytesIn = n;
					_codec.totalBytesIn += p - _codec.nextIn;
					_codec.nextIn = p;
					writeAt = q;
					return flush(r);

				version (none) //todo remove
                {
				default:
					r = ZipResult.Z_STREAM_ERROR;

					bitb = b;
                    bitk = k;
					_codec.AvailableBytesIn = n;
					_codec.TotalBytesIn += p - _codec.NextIn;
					_codec.NextIn = p;
					writeAt = q;
					return flush(r);
                }
			}
		}

		assert(0);
	}

	final void free()
	{
		reset();
		window = null;
		hufts = null;
	}

	final void setDictionary(scope const(ubyte)[] d)
	in
    {
		assert(d.length < int.max);
    }
	do
	{
		window[0..d.length] = d[0..d.length]; // Use range to make copy
		readAt = writeAt = cast(int)d.length;
	}

	// Returns true if inflate is currently at the end of a block generated
	// by Z_SYNC_FLUSH or Z_FULL_FLUSH.
	final int syncPoint()
	{
		return mode == InflateBlockMode.LENS ? 1 : 0;
	}

private:
	// copy as much as possible from the sliding window to the output area
	final int flush(int r)
	{
		int nBytes;

		for (int pass = 0; pass < 2; pass++)
		{
			if (pass == 0)
			{
				// compute number of bytes to copy as far as end of window
				nBytes = cast(int)((readAt <= writeAt ? writeAt : end) - readAt);
			}
			else
			{
				// compute bytes to copy
				nBytes = writeAt - readAt;
			}

			// workitem 8870
			if (nBytes == 0)
			{
				if (r == ZipResult.Z_BUF_ERROR)
					r = ZipResult.Z_OK;
				return r;
			}

			if (nBytes > _codec.availableBytesOut)
				nBytes = cast(int)_codec.availableBytesOut;

			if (nBytes != 0 && r == ZipResult.Z_BUF_ERROR)
				r = ZipResult.Z_OK;

			// update counters
			_codec.availableBytesOut -= nBytes;
			_codec.totalBytesOut += nBytes;

			// update check information
			if (checkfn !is null)
				check = _codec.resetAdler32(check, window[readAt..readAt + nBytes]);

			// copy as far as end of window
			_codec.outputBuffer[_codec.nextOut.._codec.nextOut + nBytes] = window[readAt..readAt + nBytes];
			_codec.nextOut += nBytes;
			readAt += nBytes;

			// see if more to copy at beginning of window
			if (readAt == end && pass == 0)
			{
				// wrap pointers
				readAt = 0;
				if (writeAt == end)
					writeAt = 0;
			}
			else
                pass++;
		}

		// done
		return r;
	}

private:
	enum int MANY = 1440;

	// Table for deflate from PKZIP's appnote.txt.
	enum const(int)[] border = [
		16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
    ];

	enum InflateBlockMode : byte
	{
		TYPE = 0,                     // get type bits (3, including end bit)
		LENS = 1,                     // get lengths for stored
		STORED = 2,                     // processing stored block
		TABLE = 3,                     // get table lengths
		BTREE = 4,                     // get bit lengths tree for a dynamic block
		DTREE = 5,                     // get length, distance trees for a dynamic block
		CODES = 6,                     // processing fixed or dynamic block
		DRY = 7,                     // output remaining window bytes
		DONE = 8,                     // finished last block, done
		BAD = 9,                     // ot a data error--stuck here
	}

	InflateBlockMode mode;                    // current inflate_block mode

	int left;                                // if STORED, bytes left to copy
	int table;                               // table lengths (14 bits)
	int index;                               // index into blens (or border)
	int[] blens;                             // bit lengths of codes
	int[] bb;                               // bit length tree depth
	int[] tb;                               // bit length decoding tree

	InflateCodes codes;                      // if CODES, current state

	int last;                                // true if this block is the last block

	ZlibCodec _codec;                        // pointer back to this zlib stream

	// mode independent information
	int bitk;                                // bits in bit buffer
	int bitb;                                // bit buffer
	int[] hufts;                             // single malloc for tree space
	ubyte[] window;                          // sliding window
	int end;                                 // one byte after sliding window
	int readAt;                              // window read pointer
	int writeAt;                             // window write pointer
	Object checkfn;                          // check function
	uint check;                              // check on output

	InfTree inftree;
}

private class InflateCodes
{
nothrow @safe:

public:
	this()
	{}

	final void init(int bl, int bd, int[] tl, int tl_index, int[] td, int td_index)
	{
		mode = InflateCodeMode.START;
		lbits = cast(ubyte)bl;
		dbits = cast(ubyte)bd;
		ltree = tl;
		ltree_index = tl_index;
		dtree = td;
		dtree_index = td_index;
		tree = null;
	}

	final int process(InflateBlocks blocks, int r)
	{
		int j;      // temporary storage
		int tindex; // temporary pointer
		int e;      // extra bits or operation
		int b = 0;  // bit buffer
		int k = 0;  // bits in bit buffer
		size_t p;   // input data pointer
		size_t n;      // bytes available there
		int q;      // output window write pointer
		int m;      // bytes to end of window or read pointer
		int f;      // pointer to copy strings from

		ZlibCodec z = blocks._codec;

		// copy input/output information to locals (UPDATE macro restores)
		p = z.nextIn;
		n = z.availableBytesIn;
		b = blocks.bitb;
		k = blocks.bitk;
		q = blocks.writeAt;
        m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;

		// process input and output based on current state
		while (true)
		{
			final switch (mode)
			{
				// waiting for "i:"=input, "o:"=output, "x:"=nothing
				case InflateCodeMode.START:  // x: set up for LEN
					if (m >= 258 && n >= 10)
					{
						blocks.bitb = b;
                        blocks.bitk = k;
						z.availableBytesIn = n;
						z.totalBytesIn += p - z.nextIn;
						z.nextIn = p;
						blocks.writeAt = q;
						r = inflateFast(lbits, dbits, ltree, ltree_index, dtree, dtree_index, blocks, z);

						p = z.nextIn;
						n = z.availableBytesIn;
						b = blocks.bitb;
						k = blocks.bitk;
						q = blocks.writeAt;
                        m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;

						if (r != ZipResult.Z_OK)
						{
							mode = (r == ZipResult.Z_STREAM_END) ? InflateCodeMode.WASH : InflateCodeMode.BADCODE;
							break;
						}
					}
					need = lbits;
					tree = ltree;
					tree_index = ltree_index;

					mode = InflateCodeMode.LEN;
					goto case InflateCodeMode.LEN;

				case InflateCodeMode.LEN:  // i: get length/literal/eob next
					j = need;

					while (k < j)
					{
						if (n != 0)
							r = ZipResult.Z_OK;
						else
						{
							blocks.bitb = b;
                            blocks.bitk = k;
							z.availableBytesIn = n;
							z.totalBytesIn += p - z.nextIn;
							z.nextIn = p;
							blocks.writeAt = q;
							return blocks.flush(r);
						}
						n--;
						b |= (z.inputBuffer[p++] & 0xff) << k;
						k += 8;
					}

					tindex = (tree_index + (b & InflateMask[j])) * 3;

					b >>= (tree[tindex + 1]);
					k -= (tree[tindex + 1]);

					e = tree[tindex];

					if (e == 0)
					{
						// literal
						lit = tree[tindex + 2];
						mode = InflateCodeMode.LIT;
						break;
					}
					if ((e & 16) != 0)
					{
						// length
						bitsToGet = e & 15;
						len = tree[tindex + 2];
						mode = InflateCodeMode.LENEXT;
						break;
					}
					if ((e & 64) == 0)
					{
						// next table
						need = e;
						tree_index = tindex / 3 + tree[tindex + 2];
						break;
					}
					if ((e & 32) != 0)
					{
						// end of block
						mode = InflateCodeMode.WASH;
						break;
					}
					mode = InflateCodeMode.BADCODE; // invalid code
					r = z.setError(ZipResult.Z_DATA_ERROR, "invalid literal/length code");
					blocks.bitb = b;
                    blocks.bitk = k;
					z.availableBytesIn = n;
					z.totalBytesIn += p - z.nextIn;
					z.nextIn = p;
					blocks.writeAt = q;
					return blocks.flush(r);

				case InflateCodeMode.LENEXT:  // i: getting length extra (have base)
					j = bitsToGet;

					while (k < j)
					{
						if (n != 0)
							r = ZipResult.Z_OK;
						else
						{
							blocks.bitb = b;
                            blocks.bitk = k;
							z.availableBytesIn = n;
                            z.totalBytesIn += p - z.nextIn;
                            z.nextIn = p;
							blocks.writeAt = q;
							return blocks.flush(r);
						}
						n--;
                        b |= (z.inputBuffer[p++] & 0xff) << k;
						k += 8;
					}

					len += (b & InflateMask[j]);

					b >>= j;
					k -= j;

					need = dbits;
					tree = dtree;
					tree_index = dtree_index;
					mode = InflateCodeMode.DIST;
					goto case InflateCodeMode.DIST;

				case InflateCodeMode.DIST:  // i: get distance next
					j = need;

					while (k < j)
					{
						if (n != 0)
							r = ZipResult.Z_OK;
						else
						{
							blocks.bitb = b;
                            blocks.bitk = k;
							z.availableBytesIn = n;
                            z.totalBytesIn += p - z.nextIn;
                            z.nextIn = p;
							blocks.writeAt = q;
							return blocks.flush(r);
						}
						n--;
                        b |= (z.inputBuffer[p++] & 0xff) << k;
						k += 8;
					}

					tindex = (tree_index + (b & InflateMask[j])) * 3;

					b >>= tree[tindex + 1];
					k -= tree[tindex + 1];

					e = (tree[tindex]);
					if ((e & 0x10) != 0)
					{
						// distance
						bitsToGet = e & 15;
						dist = tree[tindex + 2];
						mode = InflateCodeMode.DISTEXT;
						break;
					}
					if ((e & 64) == 0)
					{
						// next table
						need = e;
						tree_index = tindex / 3 + tree[tindex + 2];
						break;
					}
					mode = InflateCodeMode.BADCODE; // invalid code
					r = z.setError(ZipResult.Z_DATA_ERROR, "invalid distance code");
					blocks.bitb = b;
                    blocks.bitk = k;
					z.availableBytesIn = n;
                    z.totalBytesIn += p - z.nextIn;
                    z.nextIn = p;
					blocks.writeAt = q;
					return blocks.flush(r);

				case InflateCodeMode.DISTEXT:  // i: getting distance extra
					j = bitsToGet;

					while (k < j)
					{
						if (n != 0)
							r = ZipResult.Z_OK;
						else
						{
							blocks.bitb = b;
                            blocks.bitk = k;
							z.availableBytesIn = n;
                            z.totalBytesIn += p - z.nextIn;
                            z.nextIn = p;
							blocks.writeAt = q;
							return blocks.flush(r);
						}
						n--;
                        b |= (z.inputBuffer[p++] & 0xff) << k;
						k += 8;
					}

					dist += (b & InflateMask[j]);

					b >>= j;
					k -= j;

					mode = InflateCodeMode.COPY;
					goto case InflateCodeMode.COPY;

				case InflateCodeMode.COPY:  // o: copying bytes in window, waiting for space
					f = q - dist;
					while (f < 0)
					{
						// modulo window size-"while" instead
						f += blocks.end; // of "if" handles invalid distances
					}
					while (len != 0)
					{
						if (m == 0)
						{
							if (q == blocks.end && blocks.readAt != 0)
							{
								q = 0; m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;
							}
							if (m == 0)
							{
								blocks.writeAt = q;
                                r = blocks.flush(r);
								q = blocks.writeAt;
                                m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;

								if (q == blocks.end && blocks.readAt != 0)
								{
									q = 0;
                                    m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;
								}

								if (m == 0)
								{
									blocks.bitb = b;
                                    blocks.bitk = k;
									z.availableBytesIn = n;
									z.totalBytesIn += p - z.nextIn;
									z.nextIn = p;
									blocks.writeAt = q;
									return blocks.flush(r);
								}
							}
						}

						blocks.window[q++] = blocks.window[f++];
                        m--;

						if (f == blocks.end)
							f = 0;
						len--;
					}
					mode = InflateCodeMode.START;
					break;

				case InflateCodeMode.LIT:  // o: got literal, waiting for output space
					if (m == 0)
					{
						if (q == blocks.end && blocks.readAt != 0)
						{
							q = 0;
                            m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;
						}
						if (m == 0)
						{
							blocks.writeAt = q;
                            r = blocks.flush(r);
							q = blocks.writeAt;
                            m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;

							if (q == blocks.end && blocks.readAt != 0)
							{
								q = 0;
                                m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;
							}
							if (m == 0)
							{
								blocks.bitb = b;
                                blocks.bitk = k;
								z.availableBytesIn = n;
                                z.totalBytesIn += p - z.nextIn;
                                z.nextIn = p;
								blocks.writeAt = q;
								return blocks.flush(r);
							}
						}
					}
					r = ZipResult.Z_OK;

					blocks.window[q++] = cast(ubyte)lit;
                    m--;

					mode = InflateCodeMode.START;
					break;

				case InflateCodeMode.WASH:  // o: got eob, possibly more output
					if (k > 7)
					{
						// return unused byte, if any
						k -= 8;
						n++;
						p--; // can always return one
					}

					blocks.writeAt = q;
                    r = blocks.flush(r);
					q = blocks.writeAt;
                    m = q < blocks.readAt ? blocks.readAt - q - 1 : blocks.end - q;

					if (blocks.readAt != blocks.writeAt)
					{
						blocks.bitb = b;
                        blocks.bitk = k;
						z.availableBytesIn = n;
                        z.totalBytesIn += p - z.nextIn;
                        z.nextIn = p;
						blocks.writeAt = q;
						return blocks.flush(r);
					}
					mode = InflateCodeMode.END;
					goto case InflateCodeMode.END;

				case InflateCodeMode.END:
					r = ZipResult.Z_STREAM_END;
					blocks.bitb = b;
                    blocks.bitk = k;
					z.availableBytesIn = n;
                    z.totalBytesIn += p - z.nextIn;
                    z.nextIn = p;
					blocks.writeAt = q;
					return blocks.flush(r);

				case InflateCodeMode.BADCODE:  // x: got error
					r = ZipResult.Z_DATA_ERROR;

					blocks.bitb = b;
                    blocks.bitk = k;
					z.availableBytesIn = n;
                    z.totalBytesIn += p - z.nextIn;
                    z.nextIn = p;
					blocks.writeAt = q;
					return blocks.flush(r);

				version (none) //todo remove
                {
				default:
					r = ZipResult.Z_STREAM_ERROR;

					blocks.bitb = b;
                    blocks.bitk = k;
					z.availableBytesIn = n;
                    z.totalBytesIn += p - z.nextIn;
                    z.nextIn = p;
					blocks.writeAt = q;
					return blocks.flush(r);
                }
			}
		}

		assert(0);
	}

	/**
	 * Called with number of bytes left to write in window at least 258
	 * (the maximum string length) and number of input bytes available
	 * at least ten.  The ten bytes are six bytes for the longest length/
	 * distance pair plus four bytes for overloading the bit buffer.
	 */
	final int inflateFast(int bl, int bd, int[] tl, int tl_index, int[] td, int td_index, InflateBlocks s, ZlibCodec z)
	{
		int t;        // temporary pointer
		int[] tp;     // temporary pointer
		int tp_index; // temporary pointer
		int e;        // extra bits or operation
		int b;        // bit buffer
		int k;        // bits in bit buffer
		size_t p;        // input data pointer
		size_t n;        // bytes available there
		int q;        // output window write pointer
		int m;        // bytes to end of window or read pointer
		int ml;       // mask for literal/length tree
		int md;       // mask for distance tree
		int c;        // bytes to copy
		int d;        // distance back to copy from
		int r;        // copy source pointer

		int tp_index_t_3; // (tp_index+t)*3

		// load input, output, bit values
		p = z.nextIn;
        n = z.availableBytesIn;
        b = s.bitb;
        k = s.bitk;
		q = s.writeAt;
        m = q < s.readAt ? s.readAt - q - 1 : s.end - q;

		// initialize masks
		ml = InflateMask[bl];
		md = InflateMask[bd];

		// do until not enough input or output space for fast loop
		do
		{
			// assume called with m >= 258 && n >= 10
			// get literal/length code
			while (k < 20)
			{
				// max bits for literal/length code
				n--;
				b |= (z.inputBuffer[p++] & 0xff) << k;
                k += 8;
			}

			t = b & ml;
			tp = tl;
			tp_index = tl_index;
			tp_index_t_3 = (tp_index + t) * 3;
			if ((e = tp[tp_index_t_3]) == 0)
			{
				b >>= (tp[tp_index_t_3 + 1]);
                k -= (tp[tp_index_t_3 + 1]);

				s.window[q++] = cast(ubyte)tp[tp_index_t_3 + 2];
				m--;
				continue;
			}

			do
			{
				b >>= (tp[tp_index_t_3 + 1]);
                k -= (tp[tp_index_t_3 + 1]);

				if ((e & 16) != 0)
				{
					e &= 15;
					c = tp[tp_index_t_3 + 2] + (cast(int)b & InflateMask[e]);

					b >>= e; k -= e;

					// decode distance base of block to copy
					while (k < 15)
					{
						// max bits for distance code
						n--;
						b |= (z.inputBuffer[p++] & 0xff) << k;
                        k += 8;
					}

					t = b & md;
					tp = td;
					tp_index = td_index;
					tp_index_t_3 = (tp_index + t) * 3;
					e = tp[tp_index_t_3];

					do
					{
						b >>= (tp[tp_index_t_3 + 1]);
                        k -= (tp[tp_index_t_3 + 1]);

						if ((e & 16) != 0)
						{
							// get extra bits to add to distance base
							e &= 15;
							while (k < e)
							{
								// get extra bits (up to 13)
								n--;
								b |= (z.inputBuffer[p++] & 0xff) << k;
                                k += 8;
							}

							d = tp[tp_index_t_3 + 2] + (b & InflateMask[e]);

							b >>= e;
                            k -= e;

							// do the copy
							m -= c;
							if (q >= d)
							{
								// offset before dest
								//  just copy
								r = q - d;
								if (q - r > 0 && 2 > (q - r))
								{
									s.window[q++] = s.window[r++]; // minimum count is three,
									s.window[q++] = s.window[r++]; // so unroll loop a little
									c -= 2;
								}
								else
								{
									s.window[q..q + 2] = s.window[r..r + 2];
									q += 2;
                                    r += 2;
                                    c -= 2;
								}
							}
							else
							{
								// else offset after destination
								r = q - d;
								do
								{
									r += s.end; // force pointer in window
								}
								while (r < 0); // covers invalid distances
								e = s.end - r;
								if (c > e)
								{
									// if source crosses,
									c -= e; // wrapped copy
									if (q - r > 0 && e > (q - r))
									{
										do
										{
											s.window[q++] = s.window[r++];
										}
										while (--e != 0);
									}
									else
									{
										s.window[q..q + e] = s.window[r..r + e];
										q += e;
                                        r += e;
                                        e = 0;
									}
									r = 0; // copy rest from start of window
								}
							}

							// copy all or what's left
							if (q - r > 0 && c > (q - r))
							{
								do
								{
									s.window[q++] = s.window[r++];
								}
								while (--c != 0);
							}
							else
							{
								s.window[q..q + c] = s.window[r..r + c];
								q += c;
                                r += c;
                                c = 0;
							}
							break;
						}
						else if ((e & 64) == 0)
						{
							t += tp[tp_index_t_3 + 2];
							t += (b & InflateMask[e]);
							tp_index_t_3 = (tp_index + t) * 3;
							e = tp[tp_index_t_3];
						}
						else
						{
							c = cast(int)(z.availableBytesIn - n);
                            c = (k >> 3) < c ? k >> 3 : c;
                            n += c;
                            p -= c;
                            k -= (c << 3);

							s.bitb = b;
                            s.bitk = k;
							z.availableBytesIn = n;
                            z.totalBytesIn += p - z.nextIn;
                            z.nextIn = p;
							s.writeAt = q;

							return z.setError(ZipResult.Z_DATA_ERROR, "invalid distance code");
						}
					}
					while (true);
					break;
				}

				if ((e & 64) == 0)
				{
					t += tp[tp_index_t_3 + 2];
					t += (b & InflateMask[e]);
					tp_index_t_3 = (tp_index + t) * 3;
					if ((e = tp[tp_index_t_3]) == 0)
					{
						b >>= (tp[tp_index_t_3 + 1]);
                        k -= (tp[tp_index_t_3 + 1]);
						s.window[q++] = cast(ubyte)tp[tp_index_t_3 + 2];
						m--;
						break;
					}
				}
				else if ((e & 32) != 0)
				{
					c = cast(int)(z.availableBytesIn - n);
                    c = (k >> 3) < c ? k >> 3 : c;
                    n += c;
                    p -= c;
                    k -= (c << 3);

					s.bitb = b;
                    s.bitk = k;
					z.availableBytesIn = n;
                    z.totalBytesIn += p - z.nextIn;
                    z.nextIn = p;
					s.writeAt = q;

					return ZipResult.Z_STREAM_END;
				}
				else
				{
					c = cast(int)(z.availableBytesIn - n);
                    c = (k >> 3) < c ? k >> 3 : c;
                    n += c;
                    p -= c;
                    k -= (c << 3);

					s.bitb = b;
                    s.bitk = k;
					z.availableBytesIn = n;
                    z.totalBytesIn += p - z.nextIn;
                    z.nextIn = p;
					s.writeAt = q;

					return z.setError(ZipResult.Z_DATA_ERROR, "invalid literal/length code");
				}
			}
			while (true);
		}
		while (m >= 258 && n >= 10);

		// not enough input or output--restore pointers and return
		c = cast(int)(z.availableBytesIn - n);
        c = (k >> 3) < c ? k >> 3 : c;
        n += c;
        p -= c;
        k -= (c << 3);

		s.bitb = b;
        s.bitk = k;
		z.availableBytesIn = n;
        z.totalBytesIn += p - z.nextIn;
        z.nextIn = p;
		s.writeAt = q;

		return ZipResult.Z_OK;
	}

private:
	// waiting for "i:"=input,
	//             "o:"=output,
	//             "x:"=nothing
	enum InflateCodeMode : byte
    {
        START = 0, // x: set up for LEN
		LEN = 1, // i: get length/literal/eob next
		LENEXT = 2, // i: getting length extra (have base)
		DIST = 3, // i: get distance next
		DISTEXT = 4, // i: getting distance extra
		COPY = 5, // o: copying bytes in window, waiting for space
		LIT = 6, // o: got literal, waiting for output space
		WASH = 7, // o: got eob, possibly still output waiting
		END = 8, // x: got eob and all data flushed
		BADCODE = 9, // x: got error
    }

	InflateCodeMode mode;        // current inflate_codes mode

	// mode dependent information
	int len;

	int[] tree;      // pointer into tree
	int tree_index;
	int need;        // bits needed

	int lit;

	// if EXT or COPY, where and how much
	int bitsToGet;   // bits to get for extra
	int dist;        // distance back to copy from

	byte lbits;      // ltree bits decoded per branch
	byte dbits;      // dtree bits decoder per branch
	int[] ltree;     // literal/length/eob tree
	int ltree_index; // literal/length/eob tree
	int[] dtree;     // distance tree
	int dtree_index; // distance tree
}
