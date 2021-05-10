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

module pham.utl.zip_deflate;

import pham.utl.zip_constant;
import pham.utl.zip_tree;
import pham.utl.zip;

nothrow @safe:

class DeflateManager
{
nothrow @safe:

public:
	this(ZlibCodec codec)
	{
		this._codec = codec;
		this.treeLiterals = new Tree();
		this.treeDistances = new Tree();
		this.treeBitLengths = new Tree();
		this.bl_count.length = ZipConst.MAX_BITS + 1;
		this.heap.length = 2 * ZipConst.L_CODES + 1;
		this.depth.length = 2 * ZipConst.L_CODES + 1;
		this.dyn_ltree.length = HEAP_SIZE * 2;
		this.dyn_dtree.length = (2 * ZipConst.D_CODES + 1) * 2; // distance tree
		this.bl_tree.length = (2 * ZipConst.BL_CODES + 1) * 2; // Huffman tree for bit lengths
	}

	final int initialize(CompressionLevel compressionLevel, int windowBits,
        CompressionStrategy compressionStrategy, bool WantRfc1950HeaderBytes, int memLevel)
    in
    {
		assert(ZipConst.windowBitsMin <= windowBits && windowBits <= ZipConst.windowBitsMax);
		assert(ZipConst.deflateMemLevelMin <= memLevel && memLevel <= ZipConst.deflateMemLevelMax);
    }
	do
	{
		this.compressionLevel = compressionLevel;
		this.compressionStrategy = compressionStrategy;
		this.WantRfc1950HeaderBytes = WantRfc1950HeaderBytes;

		w_bits = windowBits;
		w_size = 1 << w_bits;
		w_mask = w_size - 1;

		hash_bits = memLevel + 7;
		hash_size = 1 << hash_bits;
		hash_mask = hash_size - 1;
		hash_shift = ((hash_bits + MIN_MATCH - 1) / MIN_MATCH);

		window.length = w_size * 2;
		prev.length = w_size;
		head.length = hash_size;

		// for memLevel==8, this will be 16384, 16k
		lit_bufsize = 1 << (memLevel + 6);

		// Use a single array as the buffer for data pending compression,
		// the output distance codes, and the output length codes (aka tree).
		// orig comment: This works just fine since the average
		// output size for (length,distance) codes is <= 24 bits.
		pending.length = lit_bufsize * 4;
		_distanceOffset = lit_bufsize;
		_lengthOffset = (1 + 2) * lit_bufsize;

		// So, for memLevel 8, the length of the pending buffer is 65536. 64k.
		// The first 16k are pending bytes.
		// The middle slice, of 32k, is used for distance codes.
		// The final 16k are length codes.

		reset();
		return ZipResult.Z_OK;
	}

	final int deflate(FlushType flush)
	{
		if ((_codec.inputBuffer.length == 0 && _codec.availableBytesIn != 0) ||
			(status == FINISH_STATE && flush != FlushType.finish))
			return _codec.setError(ZipResult.Z_ERRNO, errorMessages[ZipResult.Z_NEED_DICT - ZipResult.Z_STREAM_ERROR]);

		if (_codec.availableBytesOut == 0)
			return _codec.setError(ZipResult.Z_DATA_ERROR, errorMessages[ZipResult.Z_NEED_DICT - ZipResult.Z_BUF_ERROR]);

		const int old_flush = last_flush;
		last_flush = cast(int)flush;

		// Write the zlib (rfc1950) header bytes
		if (status == INIT_STATE)
		{
			int level_flags = ((cast(int)compressionLevel - 1) & 0xff) >> 1;
			if (level_flags > 3)
				level_flags = 3;

			int header = (Z_DEFLATED + ((w_bits - 8) << 4)) << 8;
			header |= (level_flags << 6);
			if (strstart != 0)
				header |= PRESET_DICT;
			header += 31 - (header % 31);

			status = BUSY_STATE;
			//putShortMSB(header);
			pending[pendingCount++] = cast(ubyte)(header >> 8);
			pending[pendingCount++] = cast(ubyte)header;

			// Save the adler32 of the preset dictionary:
			if (strstart != 0)
			{
				pending[pendingCount++] = cast(ubyte)((_codec.adler32 & 0xFF000000) >> 24);
				pending[pendingCount++] = cast(ubyte)((_codec.adler32 & 0x00FF0000) >> 16);
				pending[pendingCount++] = cast(ubyte)((_codec.adler32 & 0x0000FF00) >> 8);
				pending[pendingCount++] = cast(ubyte)(_codec.adler32 & 0x000000FF);
			}

			_codec.resetAdler32(0, null);
		}

		// Flush as much pending output as possible
		if (pendingCount != 0)
		{
			_codec.flushPending();
			if (_codec.availableBytesOut == 0)
			{
				//System.out.println("  avail_out==0");
				// Since avail_out is 0, deflate will be called again with
				// more output space, but possibly with both pending and
				// avail_in equal to zero. There won't be anything to do,
				// but this is not an error situation so make sure we
				// return OK instead of BUF_ERROR at next call of deflate:
				last_flush = -1;
				return ZipResult.Z_OK;
			}

			// Make sure there is something to do and avoid duplicate consecutive
			// flushes. For repeated and useless calls with Z_FINISH, we keep
			// returning Z_STREAM_END instead of Z_BUFF_ERROR.
		}
		else if (_codec.availableBytesIn == 0 &&
				 cast(int)flush <= old_flush &&
				 flush != FlushType.finish)
		{
			// workitem 8557
			//
			// Not sure why this needs to be an error.  pendingCount == 0, which
			// means there's nothing to deflate. And the caller has not asked
			// for a FlushType.Finish, but... that seems very non-fatal. We
			// can just say "OK" and do nothing.

			// _codec.Message = z_errmsg[ZipResult.Z_NEED_DICT - ZipResult.Z_BUF_ERROR];
			// throw new ZlibException("availableBytesIn == 0 && flush<=old_flush && flush != FlushType.Finish");

			return ZipResult.Z_OK;
		}

		// User must not provide more input after the first FINISH:
		if (status == FINISH_STATE && _codec.availableBytesIn != 0)
		{
			return _codec.setError(ZipResult.Z_STREAM_ERROR,
				errorMessages[ZipResult.Z_NEED_DICT - ZipResult.Z_BUF_ERROR] ~
				"\nstatus == FINISH_STATE && _codec.availableBytesIn != 0");
		}

		// Start a new block or continue the current one.
		if (_codec.availableBytesIn != 0
            || lookahead != 0
            || (flush != FlushType.none && status != FINISH_STATE))
		{
			const BlockState bstate = DeflateFunction(flush);

			if (bstate == BlockState.finishStarted || bstate == BlockState.finishDone)
			{
				status = FINISH_STATE;
			}
			if (bstate == BlockState.needMore || bstate == BlockState.finishStarted)
			{
				if (_codec.availableBytesOut == 0)
				{
					last_flush = -1; // avoid BUF_ERROR next call, see above
				}
				return ZipResult.Z_OK;
				// If flush != Z_NO_FLUSH && avail_out == 0, the next call
				// of deflate should use the same flush parameter to make sure
				// that the flush is complete. So we don't have to output an
				// empty block here, this will be done at next call. This also
				// ensures that for a very small output buffer, we emit at most
				// one empty block.
			}

			if (bstate == BlockState.blockDone)
			{
				if (flush == FlushType.partial)
				{
					trAlign();
				}
				else
				{
					// FlushType.Full or FlushType.Sync
					trStoredBlock(0, 0, false);
					// For a full flush, this empty block will be recognized
					// as a special marker by inflate_sync().
					if (flush == FlushType.full)
					{
						// clear hash (forget the history)
						head[0..hash_size] = 0;
					}
				}
				_codec.flushPending();
				if (_codec.availableBytesOut == 0)
				{
					last_flush = -1; // avoid BUF_ERROR at next call, see above
					return ZipResult.Z_OK;
				}
			}
		}

		if (flush != FlushType.finish)
			return ZipResult.Z_OK;

		if (!WantRfc1950HeaderBytes || Rfc1950BytesEmitted)
			return ZipResult.Z_STREAM_END;

		// Write the zlib trailer (adler32)
		pending[pendingCount++] = cast(ubyte)((_codec.adler32 & 0xFF000000) >> 24);
		pending[pendingCount++] = cast(ubyte)((_codec.adler32 & 0x00FF0000) >> 16);
		pending[pendingCount++] = cast(ubyte)((_codec.adler32 & 0x0000FF00) >> 8);
		pending[pendingCount++] = cast(ubyte)(_codec.adler32 & 0x000000FF);

		_codec.flushPending();

		// If avail_out is zero, the application will call deflate again
		// to flush the rest.

		Rfc1950BytesEmitted = true; // write the trailer only once!

		return pendingCount != 0 ? ZipResult.Z_OK : ZipResult.Z_STREAM_END;
	}

	final int end()
	{
		if (status != INIT_STATE && status != BUSY_STATE && status != FINISH_STATE)
			return ZipResult.Z_STREAM_ERROR;

		// Deallocate in reverse order of allocations:
		pending = null;
		head = null;
		prev = null;
		window = null;
		// free
		// dstate=null;
		return status == BUSY_STATE ? ZipResult.Z_DATA_ERROR : ZipResult.Z_OK;
	}

	final void initializeBlocks()
	{
		// Initialize the trees.
		for (int i = 0; i < ZipConst.L_CODES; i++)
			dyn_ltree[i * 2] = 0;
		for (int i = 0; i < ZipConst.D_CODES; i++)
			dyn_dtree[i * 2] = 0;
		for (int i = 0; i < ZipConst.BL_CODES; i++)
			bl_tree[i * 2] = 0;

		dyn_ltree[END_BLOCK * 2] = 1;
		opt_len = static_len = 0;
		last_lit = matches = 0;
	}

	/**
	 * Restore the heap property by moving down the tree starting at node k,
	 * exchanging a node with the smallest of its two sons if necessary, stopping
	 * when the heap property is re-established (each father smaller than its
	 * two sons).
	 */
	final void pqDownHeap(short[] tree, int k)
	{
		int v = heap[k];
		int j = k << 1; // left son of k
		while (j <= heap_len)
		{
			// Set j to the smallest of the two sons:
			if (j < heap_len && isSmaller(tree, heap[j + 1], heap[j], depth))
			{
				j++;
			}
			// Exit if v is smaller than both sons
			if (isSmaller(tree, v, heap[j], depth))
				break;

			// Exchange v with the smallest son
			heap[k] = heap[j];
            k = j;
			// And continue down the tree, setting j to the left son of k
			j <<= 1;
		}
		heap[k] = v;
	}

	final typeof(this) reset()
	{
		//strm.data_type = Z_UNKNOWN;

		pendingCount = 0;
		nextPending = 0;

		Rfc1950BytesEmitted = false;

		status = WantRfc1950HeaderBytes ? INIT_STATE : BUSY_STATE;

		last_flush = cast(int)FlushType.none;

		initializeTreeData();
		initializeLazyMatch();

		return this;
	}

	final int setParams(CompressionLevel level, CompressionStrategy strategy)
	{
		int result = ZipResult.Z_OK;
		if (this.compressionLevel == level || this.compressionStrategy == strategy)
			return result;

		// Flush existing before changing
		if (_codec.nextIn != 0 || _codec.availableBytesIn != 0)
		{
			// Flush the last buffer:
			result = _codec.deflate(FlushType.partial);
		}

		if (this.compressionLevel != level)
		{
			this.compressionLevel = level;
			config = Config.lookup(level);
		}

		this.compressionStrategy = strategy;

		setDeflater();

		return result;
	}

	final int setDictionary(scope const(ubyte)[] dictionary)
	in
    {
		assert(dictionary.length != 0 && dictionary.length < int.max);
    }
	do
	{
		if (status != INIT_STATE)
			return ZipResult.Z_ERRNO;

		size_t length = dictionary.length;
		size_t index = 0;

		//TODO range should based on dictionary[index..index + length]
		_codec.updateAdler32(dictionary);

		if (length < MIN_MATCH)
			return ZipResult.Z_OK;

		if (length > w_size - MIN_LOOKAHEAD)
		{
			length = w_size - MIN_LOOKAHEAD;
			index = dictionary.length - length; // use the tail of the dictionary
		}

		window[0..length] = dictionary[index..index + length];
		strstart = cast(int)length;
		block_start = cast(int)length;

		// Insert all strings in the hash table (except for the last two bytes).
		// s->lookahead stays null, so s->ins_h will be recomputed at the next
		// call of fill_window.

		ins_h = window[0] & 0xff;
		ins_h = (((ins_h) << hash_shift) ^ (window[1] & 0xff)) & hash_mask;

		for (int n = 0; n <= length - MIN_MATCH; n++)
		{
			ins_h = (((ins_h) << hash_shift) ^ (window[(n) + (MIN_MATCH - 1)] & 0xff)) & hash_mask;
			prev[n & w_mask] = head[ins_h];
			head[ins_h] = cast(short)n;
		}
		return ZipResult.Z_OK;
	}

public:
	ubyte[] pending;   // output still pending - waiting to be compressed
	uint nextPending;  // index of next pending byte to output to the stream
	uint pendingCount; // number of bytes in the pending buffer

	bool WantRfc1950HeaderBytes = true;

private:
	// lm_init
	final void initializeLazyMatch()
	{
		window_size = 2 * w_size;

		// clear the hash - workitem 9063
		head[0..hash_size] = 0;

		config = Config.lookup(compressionLevel);
		setDeflater();

		strstart = 0;
		block_start = 0;
		lookahead = 0;
		match_length = prev_length = MIN_MATCH - 1;
		match_available = 0;
		ins_h = 0;
	}

	// Initialize the tree data structures for a new zlib stream.
	final void initializeTreeData()
	{
		treeLiterals.dyn_tree = dyn_ltree;
		treeLiterals.staticTree = StaticTree.Literals;

		treeDistances.dyn_tree = dyn_dtree;
		treeDistances.staticTree = StaticTree.Distances;

		treeBitLengths.dyn_tree = bl_tree;
		treeBitLengths.staticTree = StaticTree.BitLengths;

		bi_buf = 0;
		bi_valid = 0;
		last_eob_len = 8; // enough lookahead for inflate

		// Initialize the first block of the first file:
		initializeBlocks();
	}

	static bool isSmaller(scope const(short)[] tree, int n, int m, scope const(byte)[] depth)
	{
		const short tn2 = tree[n * 2];
		const short tm2 = tree[m * 2];
		return (tn2 < tm2 || (tn2 == tm2 && depth[n] <= depth[m]));
	}

	/**
	 * Scan a literal or distance tree to determine the frequencies of the codes
	 * in the bit length tree.
	 */
	final void scanTree(scope short[] tree, int max_code)
	{
		int n; // iterates over all tree elements
		int prevlen = -1; // last emitted length
		int curlen; // length of current code
		int nextlen = cast(int)tree[0 * 2 + 1]; // length of next code
		int count = 0; // repeat count of the current code
		int max_count = 7; // max repeat count
		int min_count = 4; // min repeat count

		if (nextlen == 0)
		{
			max_count = 138;
            min_count = 3;
		}
		tree[(max_code + 1) * 2 + 1] = cast(short)0x7fff; // guard //??

		for (n = 0; n <= max_code; n++)
		{
			curlen = nextlen;
            nextlen = cast(int)tree[(n + 1) * 2 + 1];
			if (++count < max_count && curlen == nextlen)
			{
				continue;
			}
			else if (count < min_count)
			{
				bl_tree[curlen * 2] = cast(short)(bl_tree[curlen * 2] + count);
			}
			else if (curlen != 0)
			{
				if (curlen != prevlen)
					bl_tree[curlen * 2]++;
				bl_tree[ZipConst.REP_3_6 * 2]++;
			}
			else if (count <= 10)
			{
				bl_tree[ZipConst.REPZ_3_10 * 2]++;
			}
			else
			{
				bl_tree[ZipConst.REPZ_11_138 * 2]++;
			}
			count = 0; prevlen = curlen;
			if (nextlen == 0)
			{
				max_count = 138;
                min_count = 3;
			}
			else if (curlen == nextlen)
			{
				max_count = 6;
                min_count = 3;
			}
			else
			{
				max_count = 7;
                min_count = 4;
			}
		}
	}

	/**
	 * Construct the Huffman tree for the bit lengths and return the index in
	 * bl_order of the last bit length code to send.
	 */
	final int buildBlTree()
	{
		// Determine the bit length frequencies for literal and distance trees
		scanTree(dyn_ltree, treeLiterals.max_code);
		scanTree(dyn_dtree, treeDistances.max_code);

		// Build the bit length tree:
		treeBitLengths.buildTree(this);
		// opt_len now includes the length of the tree representations, except
		// the lengths of the bit lengths codes and the 5+5+4 bits for the counts.

		int max_blindex; // index of last bit length code of non zero freq
		// Determine the number of bit length codes to send. The pkzip format
		// requires that at least 4 bit length codes be sent. (appnote.txt says
		// 3 but the actual value used is 4.)
		for (max_blindex = ZipConst.BL_CODES - 1; max_blindex >= 3; max_blindex--)
		{
			if (bl_tree[Tree.bl_order[max_blindex] * 2 + 1] != 0)
				break;
		}
		// Update opt_len to include the bit length tree and counts
		opt_len += 3 * (max_blindex + 1) + 5 + 5 + 4;

		return max_blindex;
	}

	/**
	 * Send the header for a block using dynamic Huffman trees: the counts, the
	 * lengths of the bit length codes, the literal tree and the distance tree.
	 * IN assertion: lcodes >= 257, dcodes >= 1, blcodes >= 4.
	 */
	final void sendAllTrees(int lcodes, int dcodes, int blcodes)
	{
		sendBits(lcodes - 257, 5); // not +255 as stated in appnote.txt
		sendBits(dcodes - 1, 5);
		sendBits(blcodes - 4, 4); // not -3 as stated in appnote.txt
		int rank; // index in bl_order
		for (rank = 0; rank < blcodes; rank++)
		{
			sendBits(bl_tree[Tree.bl_order[rank] * 2 + 1], 3);
		}
		sendTree(dyn_ltree, lcodes - 1); // literal tree
		sendTree(dyn_dtree, dcodes - 1); // distance tree
	}

	/**
	 * Send a literal or distance tree in compressed form, using the codes in
	 * bl_tree.
	 */
	final void sendTree(scope const(short)[] tree, int max_code)
	{
		int n;                           // iterates over all tree elements
		int prevlen = -1;              // last emitted length
		int curlen;                      // length of current code
		int nextlen = tree[0 * 2 + 1]; // length of next code
		int count = 0;               // repeat count of the current code
		int max_count = 7;               // max repeat count
		int min_count = 4;               // min repeat count

		if (nextlen == 0)
		{
			max_count = 138;
            min_count = 3;
		}

		for (n = 0; n <= max_code; n++)
		{
			curlen = nextlen;
            nextlen = tree[(n + 1) * 2 + 1];
			if (++count < max_count && curlen == nextlen)
			{
				continue;
			}
			else if (count < min_count)
			{
				do
				{
					sendCode(curlen, bl_tree);
				}
				while (--count != 0);
			}
			else if (curlen != 0)
			{
				if (curlen != prevlen)
				{
					sendCode(curlen, bl_tree);
                    count--;
				}
				sendCode(ZipConst.REP_3_6, bl_tree);
				sendBits(count - 3, 2);
			}
			else if (count <= 10)
			{
				sendCode(ZipConst.REPZ_3_10, bl_tree);
				sendBits(count - 3, 3);
			}
			else
			{
				sendCode(ZipConst.REPZ_11_138, bl_tree);
				sendBits(count - 11, 7);
			}
			count = 0;
            prevlen = curlen;
			if (nextlen == 0)
			{
				max_count = 138;
                min_count = 3;
			}
			else if (curlen == nextlen)
			{
				max_count = 6;
                min_count = 3;
			}
			else
			{
				max_count = 7;
                min_count = 4;
			}
		}
	}

	/**
	 * Output a block of bytes on the stream.
	 * IN assertion: there is enough room in pending_buf.
	 */
	void putBytes(scope const(ubyte)[] p)
	{
		pending[pendingCount..pendingCount + p.length] = p[0..p.length];
		pendingCount += p.length;
	}

	version (NOTNEEDED)
    void putByte(ubyte c)
    {
        pending[pendingCount++] = c;
    }

	version (NOTNEEDED)
    void putShort(ushort b)
    {
        pending[pendingCount++] = cast(ubyte)b;
        pending[pendingCount++] = cast(ubyte)(b >> 8);
    }

	version (NOTNEEDED)
    void putShortMSB(ushort b)
    {
        pending[pendingCount++] = cast(ubyte)(b >> 8);
        pending[pendingCount++] = cast(ubyte)b;
    }

	final void sendCode(int c, scope const(short)[] tree)
	{
		const int c2 = c * 2;
		sendBits((tree[c2] & 0xffff), (tree[c2 + 1] & 0xffff));
	}

	final void sendBits(int value, int length)
	{
		const int len = length;

		if (bi_valid > cast(int)Buf_size - len)
		{
			//int val = value;
			//      bi_buf |= (val << bi_valid);

			bi_buf |= cast(short)((value << bi_valid) & 0xffff);
			//put_short(bi_buf);
			pending[pendingCount++] = cast(ubyte)bi_buf;
			pending[pendingCount++] = cast(ubyte)(bi_buf >> 8);

			bi_buf = cast(short)(cast(uint)value >> (Buf_size - bi_valid));
			bi_valid += len - Buf_size;
		}
		else
		{
			//      bi_buf |= (value) << bi_valid;
			bi_buf |= cast(short)((value << bi_valid) & 0xffff);
			bi_valid += len;
		}
	}

	/**
	 * Send one empty static block to give enough lookahead for inflate.
	 * This takes 10 bits, of which 7 may remain in the bit buffer.
	 * The current inflate code requires 9 bits of lookahead. If the
	 * last two codes for the previous block (real code plus EOB) were coded
	 * on 5 bits or less, inflate may have only 5+3 bits of lookahead to decode
	 * the last real code. In this case we send two empty static blocks instead
	 * of one. (There are no problems if the previous block is stored or fixed.)
	 * To simplify the code, we assume the worst case of last real code encoded
	 * on one bit only.
	 */
	final void trAlign()
	{
		sendBits(STATIC_TREES << 1, 3);
		sendCode(END_BLOCK, StaticTree.lengthAndLiteralsTreeCodes);

		biFlush();

		// Of the 10 bits for the empty block, we have already sent
		// (10 - bi_valid) bits. The lookahead for the last real code (before
		// the EOB of the previous block) was thus at least one plus the length
		// of the EOB plus what we have just sent of the empty static block.
		if (1 + last_eob_len + 10 - bi_valid < 9)
		{
			sendBits(STATIC_TREES << 1, 3);
			sendCode(END_BLOCK, StaticTree.lengthAndLiteralsTreeCodes);
			biFlush();
		}
		last_eob_len = 7;
	}

	/**
	 * Save the match info and tally the frequency counts. Return true if
	 * the current block must be flushed.
	 */
	final bool trTally(int dist, int lc)
	{
		pending[_distanceOffset + last_lit * 2] = cast(ubyte)(cast(uint)dist >> 8);
		pending[_distanceOffset + last_lit * 2 + 1] = cast(ubyte)dist;
		pending[_lengthOffset + last_lit] = cast(ubyte)lc;
		last_lit++;

		if (dist == 0)
		{
			// lc is the unmatched char
			dyn_ltree[lc * 2]++;
		}
		else
		{
			matches++;
			// Here, lc is the match length - MIN_MATCH
			dist--; // dist = match distance - 1
			dyn_ltree[(Tree.LengthCode[lc] + ZipConst.LITERALS + 1) * 2]++;
			dyn_dtree[Tree.distanceCode(dist) * 2]++;
		}

		if ((last_lit & 0x1fff) == 0 && cast(int)compressionLevel > 2)
		{
			// Compute an upper bound for the compressed length
			int out_length = last_lit << 3;
			const int in_length = strstart - block_start;
			int dcode;
			for (dcode = 0; dcode < ZipConst.D_CODES; dcode++)
			{
				out_length = cast(int)(out_length + cast(int)dyn_dtree[dcode * 2] * (5L + Tree.ExtraDistanceBits[dcode]));
			}
			out_length >>= 3;
			if ((matches < (last_lit / 2)) && out_length < in_length / 2)
				return true;
		}

		return (last_lit == lit_bufsize - 1) || (last_lit == lit_bufsize);
		// dinoch - wraparound?
		// We avoid equality with lit_bufsize because of wraparound at 64K
		// on 16 bit machines and because stored blocks are restricted to
		// 64K-1 bytes.
	}

	// Send the block data compressed using the given Huffman trees
	final void sendCompressedBlock(scope const(short)[] ltree, scope const(short)[] dtree)
	{
		int distance; // distance of matched string
		int lc;       // match length or unmatched char (if dist == 0)
		int lx = 0;   // running index in l_buf
		int code;     // the code to send
		int extra;    // number of extra bits to send

		if (last_lit != 0)
		{
			do
			{
				const int ix = _distanceOffset + lx * 2;
				distance = ((pending[ix] << 8) & 0xff00) | (pending[ix + 1] & 0xff);
				lc = (pending[_lengthOffset + lx]) & 0xff;
				lx++;

				if (distance == 0)
				{
					sendCode(lc, ltree); // send a literal byte
				}
				else
				{
					// literal or match pair
					// Here, lc is the match length - MIN_MATCH
					code = Tree.LengthCode[lc];

					// send the length code
					sendCode(code + ZipConst.LITERALS + 1, ltree);
					extra = Tree.ExtraLengthBits[code];
					if (extra != 0)
					{
						// send the extra length bits
						lc -= Tree.LengthBase[code];
						sendBits(lc, extra);
					}
					distance--; // dist is now the match distance - 1
					code = Tree.distanceCode(distance);

					// send the distance code
					sendCode(code, dtree);

					extra = Tree.ExtraDistanceBits[code];
					if (extra != 0)
					{
						// send the extra distance bits
						distance -= Tree.DistanceBase[code];
						sendBits(distance, extra);
					}
				}

				// Check that the overlay between pending and d_buf+l_buf is ok:
			}
			while (lx < last_lit);
		}

		sendCode(END_BLOCK, ltree);
		last_eob_len = ltree[END_BLOCK * 2 + 1];
	}

	/**
	 * Set the data type to ASCII or BINARY, using a crude approximation:
	 * binary if more than 20% of the bytes are <= 6 or >= 128, ascii otherwise.
	 * IN assertion: the fields freq of dyn_ltree are set and the total of all
	 * frequencies does not exceed 64K (to fit in an int on 16 bit machines).
	 */
	final void setDataType()
	{
		int n = 0;
		int ascii_freq = 0;
		int bin_freq = 0;
		while (n < 7)
		{
			bin_freq += dyn_ltree[n * 2]; n++;
		}
		while (n < 128)
		{
			ascii_freq += dyn_ltree[n * 2]; n++;
		}
		while (n < ZipConst.LITERALS)
		{
			bin_freq += dyn_ltree[n * 2]; n++;
		}
		data_type = cast(byte)(bin_freq > (ascii_freq >> 2) ? Z_BINARY : Z_ASCII);
	}

	// Flush the bit buffer, keeping at most 7 bits in it.
	final void biFlush()
	{
		if (bi_valid == 16)
		{
			pending[pendingCount++] = cast(ubyte)bi_buf;
			pending[pendingCount++] = cast(ubyte)(bi_buf >> 8);
			bi_buf = 0;
			bi_valid = 0;
		}
		else if (bi_valid >= 8)
		{
			//put_byte((byte)bi_buf);
			pending[pendingCount++] = cast(ubyte)bi_buf;
			bi_buf >>= 8;
			bi_valid -= 8;
		}
	}

	// Flush the bit buffer and align the output on a byte boundary
	final void biWindup()
	{
		if (bi_valid > 8)
		{
			pending[pendingCount++] = cast(ubyte)bi_buf;
			pending[pendingCount++] = cast(ubyte)(bi_buf >> 8);
		}
		else if (bi_valid > 0)
		{
			//put_byte(cast(ubyte)bi_buf);
			pending[pendingCount++] = cast(ubyte)bi_buf;
		}
		bi_buf = 0;
		bi_valid = 0;
	}

	/**
	 * Copy a stored block, storing first the length and its
	 * one's complement if requested.
	 */
	final void copyBlock(uint start, uint len, bool header)
	{
		biWindup(); // align on byte boundary
		last_eob_len = 8; // enough lookahead for inflate

		if (header)
		{
			//put_short(cast(short)len);
			pending[pendingCount++] = cast(ubyte)len;
			pending[pendingCount++] = cast(ubyte)(len >> 8);
			//put_short(cast(short)~len);
			pending[pendingCount++] = cast(ubyte)~len;
			pending[pendingCount++] = cast(ubyte)(~len >> 8);
		}

		putBytes(window[start..start + len]);
	}

	final void flushBlockOnly(bool eof)
	{
		trFlushBlock(block_start >= 0 ? block_start : -1, strstart - block_start, eof);
		block_start = strstart;
		_codec.flushPending();
	}

	/**
	 * Copy without compression as much as possible from the input stream, return
	 * the current block state.
	 * This function does not insert new strings in the dictionary since
	 * uncompressible data is probably not useful. This function is used
	 * only for the level=0 compression option.
	 * NOTE: this function should be optimized to avoid extra copying from
	 * window to pending_buf.
	 */
	final BlockState deflateNone(FlushType flush)
	{
		// Stored blocks are limited to 0xffff bytes, pending is limited
		// to pending_buf_size, and each stored block has a 5 byte header:

		const max_block_size = cast(int)(0xffff > pending.length - 5 ? pending.length - 5 : 0xffff);

		// Copy as much as possible from input to output:
		while (true)
		{
			// Fill the window as much as possible:
			if (lookahead <= 1)
			{
				fillWindow();
				if (lookahead == 0 && flush == FlushType.none)
					return BlockState.needMore;
				if (lookahead == 0)
					break; // flush the current block
			}

			strstart += lookahead;
			lookahead = 0;

			// Emit a stored block if pending will be full:
			const int max_start = block_start + max_block_size;
			if (strstart == 0 || strstart >= max_start)
			{
				// strstart == 0 is possible when wraparound on 16-bit machine
				lookahead = cast(int)(strstart - max_start);
				strstart = cast(int)max_start;

				flushBlockOnly(false);
				if (_codec.availableBytesOut == 0)
					return BlockState.needMore;
			}

			// Flush if we may have to slide, otherwise block_start may become
			// negative and the data will be gone:
			if (strstart - block_start >= w_size - MIN_LOOKAHEAD)
			{
				flushBlockOnly(false);
				if (_codec.availableBytesOut == 0)
					return BlockState.needMore;
			}
		}

		flushBlockOnly(flush == FlushType.finish);
		if (_codec.availableBytesOut == 0)
			return (flush == FlushType.finish) ? BlockState.finishStarted : BlockState.needMore;

		return flush == FlushType.finish ? BlockState.finishDone : BlockState.blockDone;
	}

	// Send a stored block
	final void trStoredBlock(int buf, int stored_len, bool eof)
	{
		sendBits((STORED_BLOCK << 1) + (eof ? 1 : 0), 3); // send block type
		copyBlock(buf, stored_len, true); // with header
	}

	/**
	 * Determine the best encoding for the current block: dynamic trees, static
	 * trees or store, and output the encoded block to the zip file.
	 */
	final void trFlushBlock(int buf, int stored_len, bool eof)
	{
		int opt_lenb, static_lenb; // opt_len and static_len in bytes
		int max_blindex = 0; // index of last bit length code of non zero freq

		// Build the Huffman trees unless a stored block is forced
		if (compressionLevel > 0)
		{
			// Check if the file is ascii or binary
			if (data_type == Z_UNKNOWN)
				setDataType();

			// Construct the literal and distance trees
			treeLiterals.buildTree(this);

			treeDistances.buildTree(this);

			// At this point, opt_len and static_len are the total bit lengths of
			// the compressed block data, excluding the tree representations.

			// Build the bit length tree for the above two trees, and get the index
			// in bl_order of the last bit length code to send.
			max_blindex = buildBlTree();

			// Determine the best encoding. Compute first the block length in bytes
			opt_lenb = (opt_len + 3 + 7) >> 3;
			static_lenb = (static_len + 3 + 7) >> 3;

			if (static_lenb <= opt_lenb)
				opt_lenb = static_lenb;
		}
		else
		{
			opt_lenb = static_lenb = stored_len + 5; // force a stored block
		}

		if (stored_len + 4 <= opt_lenb && buf != -1)
		{
			// 4: two words for the lengths
			// The test buf != NULL is only necessary if LIT_BUFSIZE > WSIZE.
			// Otherwise we can't have processed more than WSIZE input bytes since
			// the last block flush, because compression would have been
			// successful. If LIT_BUFSIZE <= WSIZE, it is never too late to
			// transform a block into a stored block.
			trStoredBlock(buf, stored_len, eof);
		}
		else if (static_lenb == opt_lenb)
		{
			sendBits((STATIC_TREES << 1) + (eof ? 1 : 0), 3);
			sendCompressedBlock(StaticTree.lengthAndLiteralsTreeCodes, StaticTree.distTreeCodes);
		}
		else
		{
			sendBits((DYN_TREES << 1) + (eof ? 1 : 0), 3);
			sendAllTrees(treeLiterals.max_code + 1, treeDistances.max_code + 1, max_blindex + 1);
			sendCompressedBlock(dyn_ltree, dyn_dtree);
		}

		// The above check is made mod 2^32, for files larger than 512 MB
		// and uLong implemented on 32 bits.

		initializeBlocks();

		if (eof)
		{
			biWindup();
		}
	}

	/**
	 * Fill the window when the lookahead becomes insufficient.
	 * Updates strstart and lookahead.
	 *
	 * IN assertion: lookahead < MIN_LOOKAHEAD
	 * OUT assertions: strstart <= window_size-MIN_LOOKAHEAD
	 *    At least one byte has been read, or avail_in == 0; reads are
	 *    performed for at least two bytes (required for the zip translate_eol
	 *    option -- not supported here).
	 */
	void fillWindow()
	{
		int n, m, p;
		int more; // Amount of free space at the end of the window.

		do
		{
			more = window_size - lookahead - strstart;

			// Deal with !@#$% 64K limit:
			if (more == 0 && strstart == 0 && lookahead == 0)
			{
				more = w_size;
			}
			else if (more == -1)
			{
				// Very unlikely, but possible on 16 bit machine if strstart == 0
				// and lookahead == 1 (input done one byte at time)
				more--;

				// If the window is almost full and there is insufficient lookahead,
				// move the upper half to the lower one to make room in the upper half.
			}
			else if (strstart >= w_size + w_size - MIN_LOOKAHEAD)
			{
				window[0..w_size] = window[w_size..w_size + w_size];
				match_start -= w_size;
				strstart -= w_size; // we now have strstart >= MAX_DIST
				block_start -= w_size;

				// Slide the hash table (could be avoided with 32 bit values
				// at the expense of memory usage). We slide even when level == 0
				// to keep the hash table consistent if we switch back to level > 0
				// later. (Using level 0 permanently is not an optimal usage of
				// zlib, so we don't care about this pathological case.)

				n = hash_size;
				p = n;
				do
				{
					m = (head[--p] & 0xffff);
					head[p] = cast(short)((m >= w_size) ? (m - w_size) : 0);
				}
				while (--n != 0);

				n = w_size;
				p = n;
				do
				{
					m = (prev[--p] & 0xffff);
					prev[p] = cast(short)((m >= w_size) ? (m - w_size) : 0);
					// If n is not on any hash chain, prev[n] is garbage but
					// its value will never be used.
				}
				while (--n != 0);
				more += w_size;
			}

			if (_codec.availableBytesIn == 0)
				return;

			// If there was no sliding:
			//    strstart <= WSIZE+MAX_DIST-1 && lookahead <= MIN_LOOKAHEAD - 1 &&
			//    more == window_size - lookahead - strstart
			// => more >= window_size - (MIN_LOOKAHEAD-1 + WSIZE + MAX_DIST-1)
			// => more >= window_size - 2*WSIZE + 2
			// In the BIG_MEM or MMAP case (not yet supported),
			//   window_size == input_size + MIN_LOOKAHEAD  &&
			//   strstart + s->lookahead <= input_size => more >= MIN_LOOKAHEAD.
			// Otherwise, window_size == 2*WSIZE so more >= 2.
			// If there was sliding, more >= WSIZE. So in all cases, more >= 2.
			const startAt = strstart + lookahead;
			n = _codec.readBuf(window[startAt..startAt + more]);
			lookahead += n;

			// Initialize the hash value now that we have some input:
			if (lookahead >= MIN_MATCH)
			{
				ins_h = window[strstart] & 0xff;
				ins_h = (((ins_h) << hash_shift) ^ (window[strstart + 1] & 0xff)) & hash_mask;
			}
			// If the whole input has less than MIN_MATCH bytes, ins_h is garbage,
			// but this is not important since only literal bytes will be emitted.
		}
		while (lookahead < MIN_LOOKAHEAD && _codec.availableBytesIn != 0);
	}

	/**
	 * Compress as much as possible from the input stream, return the current
	 * block state.
	 * This function does not perform lazy evaluation of matches and inserts
	 * new strings in the dictionary only for unmatched strings or for short
	 * matches. It is used only for the fast compression options.
	 */
	final BlockState deflateFast(FlushType flush)
	{
		//    short hash_head = 0; // head of the hash chain
		int hash_head = 0; // head of the hash chain
		bool bflush; // set if current block must be flushed

		while (true)
		{
			// Make sure that we always have enough lookahead, except
			// at the end of the input file. We need MAX_MATCH bytes
			// for the next match, plus MIN_MATCH bytes to insert the
			// string following the next match.
			if (lookahead < MIN_LOOKAHEAD)
			{
				fillWindow();
				if (lookahead < MIN_LOOKAHEAD && flush == FlushType.none)
				{
					return BlockState.needMore;
				}
				if (lookahead == 0)
					break; // flush the current block
			}

			// Insert the string window[strstart .. strstart+2] in the
			// dictionary, and set hash_head to the head of the hash chain:
			if (lookahead >= MIN_MATCH)
			{
				ins_h = (((ins_h) << hash_shift) ^ (window[(strstart) + (MIN_MATCH - 1)] & 0xff)) & hash_mask;

				//  prev[strstart&w_mask]=hash_head=head[ins_h];
				hash_head = (head[ins_h] & 0xffff);
				prev[strstart & w_mask] = head[ins_h];
				head[ins_h] = cast(short)strstart;
			}

			// Find the longest match, discarding those <= prev_length.
			// At this point we have always match_length < MIN_MATCH

			if (hash_head != 0L && ((strstart - hash_head) & 0xffff) <= w_size - MIN_LOOKAHEAD)
			{
				// To simplify the code, we prevent matches with the string
				// of window index 0 (in particular we have to avoid a match
				// of the string with itself at the start of the input file).
				if (compressionStrategy != CompressionStrategy.huffmanOnly)
				{
					match_length = longestMatch(hash_head);
				}
				// longestMatch() sets match_start
			}
			if (match_length >= MIN_MATCH)
			{
				//        check_match(strstart, match_start, match_length);

				bflush = trTally(strstart - match_start, match_length - MIN_MATCH);

				lookahead -= match_length;

				// Insert new strings in the hash table only if the match length
				// is not too large. This saves time but degrades compression.
				if (match_length <= config.MaxLazy && lookahead >= MIN_MATCH)
				{
					match_length--; // string at strstart already in hash table
					do
					{
						strstart++;

						ins_h = ((ins_h << hash_shift) ^ (window[(strstart) + (MIN_MATCH - 1)] & 0xff)) & hash_mask;
						//      prev[strstart&w_mask]=hash_head=head[ins_h];
						hash_head = (head[ins_h] & 0xffff);
						prev[strstart & w_mask] = head[ins_h];
						head[ins_h] = cast(short)strstart;

						// strstart never exceeds WSIZE-MAX_MATCH, so there are
						// always MIN_MATCH bytes ahead.
					}
					while (--match_length != 0);
					strstart++;
				}
				else
				{
					strstart += match_length;
					match_length = 0;
					ins_h = window[strstart] & 0xff;

					ins_h = (((ins_h) << hash_shift) ^ (window[strstart + 1] & 0xff)) & hash_mask;
					// If lookahead < MIN_MATCH, ins_h is garbage, but it does not
					// matter since it will be recomputed at next deflate call.
				}
			}
			else
			{
				// No match, output a literal byte

				bflush = trTally(0, window[strstart] & 0xff);
				lookahead--;
				strstart++;
			}
			if (bflush)
			{
				flushBlockOnly(false);
				if (_codec.availableBytesOut == 0)
					return BlockState.needMore;
			}
		}

		flushBlockOnly(flush == FlushType.finish);
		if (_codec.availableBytesOut == 0)
		{
			if (flush == FlushType.finish)
				return BlockState.finishStarted;
			else
				return BlockState.needMore;
		}
		return flush == FlushType.finish ? BlockState.finishDone : BlockState.blockDone;
	}

	/**
	 * Same as above, but achieves better compression. We use a lazy
	 * evaluation for matches: a match is finally adopted only if there is
	 * no better match at the next window position.
	 */
	final BlockState deflateSlow(FlushType flush)
	{
		//    short hash_head = 0;    // head of hash chain
		int hash_head = 0; // head of hash chain
		bool bflush; // set if current block must be flushed

		// Process the input block.
		while (true)
		{
			// Make sure that we always have enough lookahead, except
			// at the end of the input file. We need MAX_MATCH bytes
			// for the next match, plus MIN_MATCH bytes to insert the
			// string following the next match.

			if (lookahead < MIN_LOOKAHEAD)
			{
				fillWindow();
				if (lookahead < MIN_LOOKAHEAD && flush == FlushType.none)
					return BlockState.needMore;

				if (lookahead == 0)
					break; // flush the current block
			}

			// Insert the string window[strstart .. strstart+2] in the
			// dictionary, and set hash_head to the head of the hash chain:

			if (lookahead >= MIN_MATCH)
			{
				ins_h = (((ins_h) << hash_shift) ^ (window[(strstart) + (MIN_MATCH - 1)] & 0xff)) & hash_mask;
				//  prev[strstart&w_mask]=hash_head=head[ins_h];
				hash_head = (head[ins_h] & 0xffff);
				prev[strstart & w_mask] = head[ins_h];
				head[ins_h] = cast(short)strstart;
			}

			// Find the longest match, discarding those <= prev_length.
			prev_length = match_length;
			prev_match = match_start;
			match_length = MIN_MATCH - 1;

			if (hash_head != 0 && prev_length < config.MaxLazy &&
				((strstart - hash_head) & 0xffff) <= w_size - MIN_LOOKAHEAD)
			{
				// To simplify the code, we prevent matches with the string
				// of window index 0 (in particular we have to avoid a match
				// of the string with itself at the start of the input file).

				if (compressionStrategy != CompressionStrategy.huffmanOnly)
				{
					match_length = longestMatch(hash_head);
				}
				// longest_match() sets match_start

				if (match_length <= 5 && (compressionStrategy == CompressionStrategy.filtered ||
										  (match_length == MIN_MATCH && strstart - match_start > 4096)))
				{

					// If prev_match is also MIN_MATCH, match_start is garbage
					// but we will ignore the current match anyway.
					match_length = MIN_MATCH - 1;
				}
			}

			// If there was a match at the previous step and the current
			// match is not better, output the previous match:
			if (prev_length >= MIN_MATCH && match_length <= prev_length)
			{
				int max_insert = strstart + lookahead - MIN_MATCH;
				// Do not insert strings in hash table beyond this.

				//          checkMatch(strstart-1, prev_match, prev_length);

				bflush = trTally(strstart - 1 - prev_match, prev_length - MIN_MATCH);

				// Insert in hash table all strings up to the end of the match.
				// strstart-1 and strstart are already inserted. If there is not
				// enough lookahead, the last two strings are not inserted in
				// the hash table.
				lookahead -= (prev_length - 1);
				prev_length -= 2;
				do
				{
					if (++strstart <= max_insert)
					{
						ins_h = (((ins_h) << hash_shift) ^ (window[(strstart) + (MIN_MATCH - 1)] & 0xff)) & hash_mask;
						//prev[strstart&w_mask]=hash_head=head[ins_h];
						hash_head = (head[ins_h] & 0xffff);
						prev[strstart & w_mask] = head[ins_h];
						head[ins_h] = cast(short)strstart;
					}
				}
				while (--prev_length != 0);
				match_available = 0;
				match_length = MIN_MATCH - 1;
				strstart++;

				if (bflush)
				{
					flushBlockOnly(false);
					if (_codec.availableBytesOut == 0)
						return BlockState.needMore;
				}
			}
			else if (match_available != 0)
			{
				// If there was no match at the previous position, output a
				// single literal. If there was a match but the current match
				// is longer, truncate the previous match to a single literal.

				bflush = trTally(0, window[strstart - 1] & 0xff);

				if (bflush)
				{
					flushBlockOnly(false);
				}
				strstart++;
				lookahead--;
				if (_codec.availableBytesOut == 0)
					return BlockState.needMore;
			}
			else
			{
				// There is no previous match to compare with, wait for
				// the next step to decide.

				match_available = 1;
				strstart++;
				lookahead--;
			}
		}

		if (match_available != 0)
		{
			bflush = trTally(0, window[strstart - 1] & 0xff);
			match_available = 0;
		}
		flushBlockOnly(flush == FlushType.finish);

		if (_codec.availableBytesOut == 0)
		{
			if (flush == FlushType.finish)
				return BlockState.finishStarted;
			else
				return BlockState.needMore;
		}

		return flush == FlushType.finish ? BlockState.finishDone : BlockState.blockDone;
	}

	final int longestMatch(int cur_match)
	{
		int chain_length = config.MaxChainLength; // max hash chain length
		int scan = strstart;              // current string
		int match;                                // matched string
		int len;                                  // length of current match
		int best_len = prev_length;           // best match length so far
		int limit = strstart > (w_size - MIN_LOOKAHEAD) ? strstart - (w_size - MIN_LOOKAHEAD) : 0;

		int niceLength = config.NiceLength;

		// Stop when cur_match becomes <= limit. To simplify the code,
		// we prevent matches with the string of window index 0.

		int wmask = w_mask;

		int strend = strstart + MAX_MATCH;
		byte scan_end1 = window[scan + best_len - 1];
		byte scan_end = window[scan + best_len];

		// The code is optimized for HASH_BITS >= 8 and MAX_MATCH-2 multiple of 16.
		// It is easy to get rid of this optimization if necessary.

		// Do not waste too much time if we already have a good match:
		if (prev_length >= config.GoodLength)
		{
			chain_length >>= 2;
		}

		// Do not look for matches beyond the end of the input. This is necessary
		// to make deflate deterministic.
		if (niceLength > lookahead)
			niceLength = lookahead;

		do
		{
			match = cur_match;

			// Skip to next match if the match length cannot increase
			// or if the match length is less than 2:
			if (window[match + best_len] != scan_end ||
				window[match + best_len - 1] != scan_end1 ||
				window[match] != window[scan] ||
				window[++match] != window[scan + 1])
				continue;

			// The check at best_len-1 can be removed because it will be made
			// again later. (This heuristic is not always a win.)
			// It is not necessary to compare scan[2] and match[2] since they
			// are always equal when the other bytes match, given that
			// the hash keys are equal and that HASH_BITS >= 8.
			scan += 2; match++;

			// We check for insufficient lookahead only every 8th comparison;
			// the 256th check will be made at strstart+258.
			do
			{
			}
			while (window[++scan] == window[++match] &&
				   window[++scan] == window[++match] &&
				   window[++scan] == window[++match] &&
				   window[++scan] == window[++match] &&
				   window[++scan] == window[++match] &&
				   window[++scan] == window[++match] &&
				   window[++scan] == window[++match] &&
				   window[++scan] == window[++match] && scan < strend);

			len = MAX_MATCH - cast(int)(strend - scan);
			scan = strend - MAX_MATCH;

			if (len > best_len)
			{
				match_start = cur_match;
				best_len = len;
				if (len >= niceLength)
					break;
				scan_end1 = window[scan + best_len - 1];
				scan_end = window[scan + best_len];
			}
		}
		while ((cur_match = (prev[cur_match & wmask] & 0xffff)) > limit && --chain_length != 0);

		if (best_len <= lookahead)
			return best_len;
		return lookahead;
	}

	void setDeflater()
	{
		final switch (config.Flavor)
		{
			case DeflateFlavor.store:
				DeflateFunction = &deflateNone;
				break;
			case DeflateFlavor.fast:
				DeflateFunction = &deflateFast;
				break;
			case DeflateFlavor.slow:
				DeflateFunction = &deflateSlow;
				break;
		}
	}

public:
	// number of codes at each bit length for an optimal tree
	short[] bl_count;

	// The sons of heap[n] are heap[2*n] and heap[2*n+1]. heap[0] is not used.
	// The same heap array is used to build all trees.
	// heap used to build the Huffman trees
	int[] heap;
	int heap_len;              // number of elements in the heap
	int heap_max;              // element of largest frequency

	int opt_len;      // bit length of current block with optimal trees
	int static_len;   // bit length of current block with static trees

	// Depth of each subtree used as tie breaker for trees of equal frequency
	byte[] depth;

private:
	alias CompressFunc = BlockState delegate(FlushType flush);

	CompressFunc DeflateFunction;

	static immutable string[] errorMessages = [
		"need dictionary",
		"stream end",
		"",
		"file error",
		"stream error",
		"data error",
		"insufficient memory",
		"buffer error",
		"incompatible version",
		""
	];

	// preset dictionary flag in zlib header
	enum int PRESET_DICT = 0x20;

	enum int INIT_STATE = 42;
	enum int BUSY_STATE = 113;
	enum int FINISH_STATE = 666;

	// The deflate compression method
	enum int Z_DEFLATED = 8;

	enum int STORED_BLOCK = 0;
	enum int STATIC_TREES = 1;
	enum int DYN_TREES = 2;

	// The three kinds of block type
	enum int Z_BINARY = 0;
	enum int Z_ASCII = 1;
	enum int Z_UNKNOWN = 2;

	enum int Buf_size = 8 * 2;

	enum int MIN_MATCH = 3;
	enum int MAX_MATCH = 258;

	enum int MIN_LOOKAHEAD = (MAX_MATCH + MIN_MATCH + 1);

	enum int HEAP_SIZE = (2 * ZipConst.L_CODES + 1);

	enum int END_BLOCK = 256;

	ZlibCodec _codec; // the zlib encoder/decoder
	int status;       // as the name implies

	byte data_type;  // UNKNOWN, BINARY or ASCII
	int last_flush;   // value of flush param for previous deflate call

	int w_size;       // LZ77 window size (32K by default)
	int w_bits;       // log2(w_size)  (8..16)
	int w_mask;       // w_size - 1

	//ubyte[] dictionary;
	ubyte[] window;

	// Sliding window. Input bytes are read into the second half of the window,
	// and move to the first half later to keep a dictionary of at least wSize
	// bytes. With this organization, matches are limited to a distance of
	// wSize-MAX_MATCH bytes, but this ensures that IO is always
	// performed with a length multiple of the block size.
	//
	// To do: use the user input buffer as sliding window.

	int window_size;
	// Actual size of window: 2*wSize, except when the user input buffer
	// is directly used as sliding window.

	short[] prev;
	// Link to older string with same hash index. To limit the size of this
	// array to 64K, this link is maintained only for the last 32K strings.
	// An index in this array is thus a window index modulo 32K.

	short[] head;  // Heads of the hash chains or NIL.

	int ins_h;     // hash index of string to be inserted
	int hash_size; // number of elements in hash table
	int hash_bits; // log2(hash_size)
	int hash_mask; // hash_size-1

	// Number of bits by which ins_h must be shifted at each input
	// step. It must be such that after MIN_MATCH steps, the oldest
	// byte no longer takes part in the hash key, that is:
	// hash_shift * MIN_MATCH >= hash_bits
	int hash_shift;

	// Window position at the beginning of the current output block. Gets
	// negative when the window is moved backwards.

	int block_start;

	Config config;
	int match_length;    // length of best match
	int prev_match;      // previous match
	int match_available; // set if previous match exists
	int strstart;        // start of string to insert into.....????
	int match_start;     // start of matching string
	int lookahead;       // number of valid bytes ahead in window

	// Length of the best match at previous step. Matches not greater than this
	// are discarded. This is used in the lazy match evaluation.
	int prev_length;

	// Insert new strings in the hash table only if the match length is not
	// greater than this length. This saves time but degrades compression.
	// max_insert_length is used only for compression levels <= 3.

	CompressionLevel compressionLevel; // compression level (1..9)
	CompressionStrategy compressionStrategy; // favor or force Huffman coding

	short[] dyn_ltree;         // literal and length tree
	short[] dyn_dtree;         // distance tree
	short[] bl_tree;           // Huffman tree for bit lengths

	Tree treeLiterals;  // desc for literal tree
	Tree treeDistances;  // desc for distance tree
	Tree treeBitLengths; // desc for bit length tree

	int _lengthOffset;                 // index for literals or lengths

	// Size of match buffer for literals/lengths.  There are 4 reasons for
	// limiting lit_bufsize to 64K:
	//   - frequencies can be kept in 16 bit counters
	//   - if compression is not successful for the first block, all input
	//     data is still in the window so we can still emit a stored block even
	//     when input comes from standard input.  (This can also be done for
	//     all blocks if lit_bufsize is not greater than 32K.)
	//   - if compression is not successful for a file smaller than 64K, we can
	//     even emit a stored file instead of a stored block (saving 5 bytes).
	//     This is applicable only for zip (not gzip or zlib).
	//   - creating new Huffman trees less frequently may not provide fast
	//     adaptation to changes in the input data statistics. (Take for
	//     example a binary file with poorly compressible code followed by
	//     a highly compressible string table.) Smaller buffer sizes give
	//     fast adaptation but have of course the overhead of transmitting
	//     trees more frequently.

	int lit_bufsize;

	int last_lit;     // running index in l_buf

	// Buffer for distances. To simplify the code, d_buf and l_buf have
	// the same number of elements. To use different lengths, an extra flag
	// array would be necessary.

	int _distanceOffset;        // index into pending; points to distance data??

	int matches;      // number of string matches in current block
	int last_eob_len; // bit length of EOB code for last block

	// Output buffer. bits are inserted starting at the bottom (least
	// significant bits).
	short bi_buf;

	// Number of valid bits in bi_buf.  All bits above the last valid bit
	// are always zero.
	int bi_valid;

	bool Rfc1950BytesEmitted;
}

private enum BlockState : byte
{
	needMore = 0,       // block not completed, need more input or more output
	blockDone,          // block flush performed
	finishStarted,              // finish started, need only more output at next deflate
	finishDone          // finish done, accept no more input or output
}

private class Config
{
nothrow @safe:

public:
	// Use a faster search when the previous match is longer than this
	const int GoodLength; // reduce lazy search above this match length

	// Attempt to find a better match only when the current match is
	// strictly smaller than this value. This mechanism is used only for
	// compression levels >= 4.  For levels 1,2,3: MaxLazy is actually
	// MaxInsertLength. (See DeflateFast)

	const int MaxLazy;    // do not perform lazy search above this match length

	const int NiceLength; // quit search above this match length

	// To speed up deflation, hash chains are never searched beyond this
	// length.  A higher limit improves compression ratio but degrades the speed.

	const int MaxChainLength;

	const DeflateFlavor Flavor;

	static Config lookup(CompressionLevel level) @trusted
	{
		return Tables[cast(int)level];
	}

	this(int goodLength, int maxLazy, int niceLength, int maxChainLength, DeflateFlavor flavor)
	{
		this.GoodLength = goodLength;
		this.MaxLazy = maxLazy;
		this.NiceLength = niceLength;
		this.MaxChainLength = maxChainLength;
		this.Flavor = flavor;
	}

private:
	shared static this() @trusted
	{
		Tables = [
			new Config(0, 0, 0, 0, DeflateFlavor.store),
			new Config(4, 4, 8, 4, DeflateFlavor.fast),
			new Config(4, 5, 16, 8, DeflateFlavor.fast),
			new Config(4, 6, 32, 32, DeflateFlavor.fast),

			new Config(4, 4, 16, 16, DeflateFlavor.slow),
			new Config(8, 16, 32, 32, DeflateFlavor.slow),
			new Config(8, 16, 128, 128, DeflateFlavor.slow),
			new Config(8, 32, 128, 256, DeflateFlavor.slow),
			new Config(32, 128, 258, 1024, DeflateFlavor.slow),
			new Config(32, 258, 258, 4096, DeflateFlavor.slow),
		];
	}

	__gshared Config[] Tables;
}
