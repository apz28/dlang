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

module pham.utl.utl_zip_tree;

import std.algorithm.comparison : max;

import pham.utl.utl_zip_constant;
import pham.utl.utl_zip_deflate;
import pham.utl.utl_zip;

nothrow @safe:

class Tree
{
nothrow @safe:

public:

    /**
     * Performs an unsigned bitwise right shift with the specified number
     * Params:
     *  number = Number to operate on
     *  bits = Ammount of bits to shift
     * Returns:
     *  The resulting number from the shift operation
     */
    static int urShift(int number, int bits) pure
    {
        return cast(int)(cast(uint)number >> bits);
    }

    /**
     * Map from a distance to a distance code.
     * No side effects. _dist_code[256] and _dist_code[257] are never used.
     */
    static int distanceCode(int dist)
    {
        return dist < 256 ? _dist_code[dist] : _dist_code[256 + urShift(dist, 7)];
    }

    /**
     * Compute the optimal bit lengths for a tree and update the total bit length
     * for the current block.
     * IN assertion: the fields freq and dad are set, heap[heap_max] and
     *    above are the tree nodes sorted by increasing frequency.
     * OUT assertions: the field len is set to the optimal bit length, the
     *     array bl_count contains the frequencies for each bit length.
     *     The length opt_len is updated; static_len is also updated if stree is
     *     not null.
     */
    final void genBitLen(DeflateManager s)
    {
        short[] tree = dyn_tree;
        short[] stree = staticTree.treeCodes.dup;
        int[] extra = staticTree.extraBits.dup;
        int base_Renamed = staticTree.extraBase;
        int max_length = staticTree.maxLength;
        int h; // heap index
        int n, m; // iterate over the tree elements
        int bits; // bit length
        int xbits; // extra bits
        short f; // frequency
        int overflow = 0; // number of elements with bit length too large

        for (bits = 0; bits <= ZipConst.MAX_BITS; bits++)
            s.bl_count[bits] = 0;

        // In a first pass, compute the optimal bit lengths (which may
        // overflow in the case of the bit length tree).
        tree[s.heap[s.heap_max] * 2 + 1] = 0; // root of the heap

        for (h = s.heap_max + 1; h < HEAP_SIZE; h++)
        {
            n = s.heap[h];
            bits = tree[tree[n * 2 + 1] * 2 + 1] + 1;
            if (bits > max_length)
            {
                bits = max_length;
                overflow++;
            }
            tree[n * 2 + 1] = cast(short)bits;
            // We overwrite tree[n*2+1] which is no longer needed

            if (n > max_code)
                continue; // not a leaf node

            s.bl_count[bits]++;
            xbits = 0;
            if (n >= base_Renamed)
                xbits = extra[n - base_Renamed];
            f = tree[n * 2];
            s.opt_len += f * (bits + xbits);
            if (stree !is null)
                s.static_len += f * (stree[n * 2 + 1] + xbits);
        }
        if (overflow == 0)
            return;

        // This happens for example on obj2 and pic of the Calgary corpus
        // Find the first bit length which could increase:
        do
        {
            bits = max_length - 1;
            while (s.bl_count[bits] == 0)
                bits--;
            s.bl_count[bits]--; // move one leaf down the tree
            s.bl_count[bits + 1] = cast(short)(s.bl_count[bits + 1] + 2); // move one overflow item as its brother
            s.bl_count[max_length]--;
            // The brother of the overflow item also moves one step up,
            // but this does not affect bl_count[max_length]
            overflow -= 2;
        }
        while (overflow > 0);

        for (bits = max_length; bits != 0; bits--)
        {
            n = s.bl_count[bits];
            while (n != 0)
            {
                m = s.heap[--h];
                if (m > max_code)
                    continue;
                if (tree[m * 2 + 1] != bits)
                {
                    s.opt_len = cast(int)(s.opt_len + (cast(long)bits - cast(long)tree[m * 2 + 1]) * cast(long)tree[m * 2]);
                    tree[m * 2 + 1] = cast(short)bits;
                }
                n--;
            }
        }
    }

    /**
     * Construct one Huffman tree and assigns the code bit strings and lengths.
     * Update the total bit length for the current block.
     * IN assertion: the field freq is set for all tree elements.
     * OUT assertions: the fields len and code are set to the optimal bit length
     *     and corresponding code. The length opt_len is updated; static_len is
     *     also updated if stree is not null. The field max_code is set.
     */
    final void buildTree(DeflateManager s)
    {
        short[] tree  = dyn_tree;
        short[] stree = staticTree.treeCodes.dup;
        int elems     = staticTree.elems;
        int n, m;            // iterate over heap elements
        int max_code  = -1;  // largest code with non zero frequency
        int node;            // new node being created

        // Construct the initial heap, with least frequent element in
        // heap[1]. The sons of heap[n] are heap[2*n] and heap[2*n+1].
        // heap[0] is not used.
        s.heap_len = 0;
        s.heap_max = HEAP_SIZE;

        for (n = 0; n < elems; n++)
        {
            if (tree[n * 2] != 0)
            {
                s.heap[++s.heap_len] = max_code = n;
                s.depth[n] = 0;
            }
            else
            {
                tree[n * 2 + 1] = 0;
            }
        }

        // The pkzip format requires that at least one distance code exists,
        // and that at least one bit should be sent even if there is only one
        // possible code. So to avoid special checks later on we force at least
        // two codes of non zero frequency.
        while (s.heap_len < 2)
        {
            node = s.heap[++s.heap_len] = (max_code < 2 ? ++max_code : 0);
            tree[node * 2] = 1;
            s.depth[node] = 0;
            s.opt_len--;
            if (stree != null)
                s.static_len -= stree[node * 2 + 1];
            // node is 0 or 1 so it does not have extra bits
        }
        this.max_code = max_code;

        // The elements heap[heap_len/2+1 .. heap_len] are leaves of the tree,
        // establish sub-heaps of increasing lengths:

        for (n = s.heap_len / 2; n >= 1; n--)
            s.pqDownHeap(tree, n);

        // Construct the Huffman tree by repeatedly combining the least two
        // frequent nodes.

        node = elems; // next node of the tree
        do
        {
            // n = node of least frequency
            n = s.heap[1];
            s.heap[1] = s.heap[s.heap_len--];
            s.pqDownHeap(tree, 1);
            m = s.heap[1]; // m = node of next least frequency

            s.heap[--s.heap_max] = n; // keep the nodes sorted by frequency
            s.heap[--s.heap_max] = m;

            // Create a new node father of n and m
            tree[node * 2] = cast(short)(tree[n * 2] + tree[m * 2]);
            s.depth[node] = cast(byte)(max(cast(ubyte)s.depth[n], cast(ubyte)s.depth[m]) + 1);
            tree[n * 2 + 1] = tree[m * 2 + 1] = cast(short)node;

            // and insert the new node in the heap
            s.heap[1] = node++;
            s.pqDownHeap(tree, 1);
        }
        while (s.heap_len >= 2);

        s.heap[--s.heap_max] = s.heap[1];

        // At this point, the fields freq and dad are set. We can now
        // generate the bit lengths.

        genBitLen(s);

        // The field len is now set, we can generate the bit codes
        genCodes(tree, max_code, s.bl_count);
    }

    /**
     * Generate the codes for a given tree and bit counts (which need not be
     * optimal).
     * IN assertion: the array bl_count contains the bit length statistics for
     * the given tree and the field len is set for all tree elements.
     * OUT assertion: the field code is set for all tree elements of non
     *     zero code length.
     */
    static void genCodes(short[] tree, int max_code, scope const(short)[] bl_count)
    {
        short[ZipConst.MAX_BITS + 1] next_code; // next code value for each bit length
        short code = 0; // running code value
        int bits; // bit index
        int n; // code index

        // The distribution counts are first used to generate the code values
        // without bit reversal.
        for (bits = 1; bits <= ZipConst.MAX_BITS; bits++)
            next_code[bits] = code = cast(short)((code + bl_count[bits - 1]) << 1);

        // Check that the bit counts in bl_count are consistent. The last code
        // must be all ones.
        //Assert (code + bl_count[MAX_BITS]-1 == (1<<MAX_BITS)-1,
        //        "inconsistent bit counts");
        //Tracev((stderr,"\ngen_codes: max_code %d ", max_code));

        for (n = 0; n <= max_code; n++)
        {
            const int len = tree[n * 2 + 1];
            if (len == 0)
                continue;
            // Now reverse the bits
            tree[n * 2] = cast(short)(biReverse(next_code[len]++, len));
        }
    }

    /**
     * Reverse the first len bits of a code, using straightforward code (a faster
     * method would use a table)
     */
    static int biReverse(int code, int len)
    in
    {
        assert(1 <= len && len <= 15);
    }
    do
    {
        int res = 0;
        do
        {
            res |= code & 1;
            code >>= 1;
            res <<= 1;
        }
        while (--len > 0);
        return res >> 1;
    }

public:
    static immutable const(ubyte)[] bl_order = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
        ];

    static immutable const(int)[] DistanceBase = [
        0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192,
        256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096, 6144, 8192, 12288, 16384, 24576
        ];

    // extra bits for each distance code
    static immutable const(int)[] ExtraDistanceBits = [
        0, 0, 0, 0, 1, 1,  2,  2,  3,  3,  4,  4,  5,  5,  6,  6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
        ];

    // extra bits for each length code
    static immutable const(int)[] ExtraLengthBits = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
        ];

    static immutable const(int)[] LengthBase = [
        0,   1,  2,  3,  4,  5,  6,   7,   8,  10,  12,  14, 16, 20, 24, 28,
        32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 0
        ];

    static immutable const(ubyte)[] LengthCode = [
        0,   1,  2,  3,  4,  5,  6,  7,  8,  8,  9,  9, 10, 10, 11, 11,
        12, 12, 12, 12, 13, 13, 13, 13, 14, 14, 14, 14, 15, 15, 15, 15,
        16, 16, 16, 16, 16, 16, 16, 16, 17, 17, 17, 17, 17, 17, 17, 17,
        18, 18, 18, 18, 18, 18, 18, 18, 19, 19, 19, 19, 19, 19, 19, 19,
        20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20,
        21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21,
        22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22,
        23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23,
        24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
        24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
        25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25,
        25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25,
        26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
        26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
        27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
        27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 28
        ];

    StaticTree staticTree; // the corresponding static tree
    short[] dyn_tree; // the dynamic tree
    int max_code; // largest code with non zero frequency

private:
    enum HEAP_SIZE = 2 * ZipConst.L_CODES + 1;

    // extra bits for each bit length code
    static immutable const(int)[] extra_blbits = [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 3, 7
        ];

    // The lengths of the bit length codes are sent in order of decreasing
    // probability, to avoid transmitting the lengths for unused bit
    // length codes.
    enum Buf_size = 8 * 2;

    // see definition of array dist_code below
    //const int DIST_CODE_LEN = 512;
    static immutable const(ubyte)[] _dist_code = [
        0,  1,  2,  3,  4,  4,  5,  5,  6,  6,  6,  6,  7,  7,  7,  7,
        8,  8,  8,  8,  8,  8,  8,  8,  9,  9,  9,  9,  9,  9,  9,  9,
        10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
        11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11, 11,
        12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
        12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12, 12,
        13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
        13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13,
        14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
        14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
        14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
        14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
        0,   0, 16, 17, 18, 18, 19, 19, 20, 20, 20, 20, 21, 21, 21, 21,
        22, 22, 22, 22, 22, 22, 22, 22, 23, 23, 23, 23, 23, 23, 23, 23,
        24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24,
        25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25, 25,
        26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
        26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26,
        27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
        27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27, 27,
        28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
        28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
        28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
        28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
        29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
        29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
        29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29,
        29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29
        ];
}

class InfTree
{
nothrow @safe:

public:
    final int inflateTreesBits(int[] c, int[] bb, int[] tb, int[] hp, ZlibCodec z)
    {
        initWorkArea(19);
        hn[] = 0;
        int result = huftBuild(c, 0, 19, 19, null, null, tb, bb, hp, hn, v);

        if (result == ZipResult.Z_DATA_ERROR)
            z.setError(ZipResult.Z_DATA_ERROR, "oversubscribed dynamic bit lengths tree");
        else if (result == ZipResult.Z_BUF_ERROR || bb[0] == 0)
            result = z.setError(ZipResult.Z_DATA_ERROR, "incomplete dynamic bit lengths tree");

        return result;
    }

    final int inflateTreesDynamic(int nl, int nd, int[] c, int[] bl, int[] bd, int[] tl, int[] td, int[] hp, ZlibCodec z)
    {
        // build literal/length tree
        initWorkArea(288);
        hn[] = 0;
        int result = huftBuild(c, 0, nl, 257, cplens, cplext, tl, bl, hp, hn, v);

        if (result != ZipResult.Z_OK || bl[0] == 0)
        {
            if (result == ZipResult.Z_DATA_ERROR)
                z.setError(ZipResult.Z_DATA_ERROR, "oversubscribed literal/length tree");
            else if (result != ZipResult.Z_MEM_ERROR)
                result = z.setError(ZipResult.Z_DATA_ERROR, "incomplete literal/length tree");

            return result;
        }

        // build distance tree
        initWorkArea(288);
        result = huftBuild(c, nl, nd, 0, cpdist, cpdext, td, bd, hp, hn, v);

        if (result != ZipResult.Z_OK || (bd[0] == 0 && nl > 257))
        {
            if (result == ZipResult.Z_DATA_ERROR)
                z.setError(ZipResult.Z_DATA_ERROR, "oversubscribed distance tree");
            else if (result == ZipResult.Z_BUF_ERROR)
                result = z.setError(ZipResult.Z_DATA_ERROR, "incomplete distance tree");
            else if (result != ZipResult.Z_MEM_ERROR)
                result = z.setError(ZipResult.Z_DATA_ERROR, "empty distance tree with lengths");

            return result;
        }

        return ZipResult.Z_OK;
    }

    static int inflateTreesFixed(ref int[] bl, ref int[] bd, ref int[][] tl, ref int[][] td, ZlibCodec z)
    {
        bl[0] = fixed_bl;
        bd[0] = fixed_bd;
        tl[0] = fixed_tl.dup;
        td[0] = fixed_td.dup;
        return ZipResult.Z_OK;
    }

private:
    final int huftBuild(int[] b, int bindex, int n, int s, const(int)[] d, const(int)[] e, int[] t, int[] m, int[] hp, int[] hn, int[] v)
    {
        // Given a list of code lengths and a maximum table size, make a set of
        // tables to decode that set of codes.  Return Z_OK on success, Z_BUF_ERROR
        // if the given code set is incomplete (the tables are still built in this
        // case), Z_DATA_ERROR if the input is invalid (an over-subscribed set of
        // lengths), or Z_MEM_ERROR if not enough memory.

        int a; // counter for codes of length k
        int f; // i repeats in table every f entries
        int g; // maximum code length
        int h; // table level
        int i; // counter, current code
        int j; // counter
        int k; // number of bits in current code
        int l; // bits per table (returned in m)
        int mask; // (1 << w) - 1, to avoid cc -O bug on HP
        int p; // pointer into c[], b[], or v[]
        int q; // points to current table
        int w; // bits before this table == (l * h)
        int xp; // pointer into x
        int y; // number of dummy codes added
        int z; // number of entries in current table

        // Generate counts for each bit length

        p = 0;
        i = n;
        do
        {
            c[b[bindex + p]]++;
            p++;
            i--; // assume all entries <= BMAX
        }
        while (i != 0);

        if (c[0] == n)
        {
            // null input--all zero length codes
            t[0] = - 1;
            m[0] = 0;
            return ZipResult.Z_OK;
        }

        // Find minimum and maximum length, bound *m by those
        l = m[0];
        for (j = 1; j <= BMAX; j++)
        {
            if (c[j] != 0)
                break;
        }
        k = j; // minimum code length
        if (l < j)
            l = j;
        for (i = BMAX; i != 0; i--)
        {
            if (c[i] != 0)
                break;
        }
        g = i; // maximum code length
        if (l > i)
            l = i;
        m[0] = l;

        // Adjust last length count to fill out codes, if needed
        for (y = 1 << j; j < i; j++, y <<= 1)
        {
            if ((y -= c[j]) < 0)
                return ZipResult.Z_DATA_ERROR;
        }
        if ((y -= c[i]) < 0)
            return ZipResult.Z_DATA_ERROR;
        c[i] += y;

        // Generate starting offsets into the value table for each length
        x[1] = j = 0;
        p = 1;
        xp = 2;
        while (--i != 0)
        {
            // note that i == g from above
            x[xp] = (j += c[p]);
            p++;
            xp++;
        }

        // Make a table of values in order of bit lengths
        i = 0; p = 0;
        do
        {
            if ((j = b[bindex + p]) != 0)
                v[x[j]++] = i;
            p++;
        }
        while (++i < n);
        n = x[g]; // set n to length of v

        // Generate the Huffman codes and for each, make the table entries
        x[0] = i = 0; // first Huffman code is zero
        p = 0; // grab values in bit order
        h = -1; // no tables yet--level -1
        w = -l; // bits decoded == (l * h)
        u[0] = 0; // just to keep compilers happy
        q = 0; // ditto
        z = 0; // ditto

        // go through the bit lengths (k already is bits in shortest code)
        for (; k <= g; k++)
        {
            a = c[k];
            while (a-- != 0)
            {
                // here i is the Huffman code of length k bits for value *p
                // make tables up to required level
                while (k > w + l)
                {
                    h++;
                    w += l; // previous table always l bits
                    // compute minimum size table less than or equal to l bits
                    z = g - w;
                    z = z > l ? l: z; // table size upper limit
                    if ((f = 1 << (j = k - w)) > a + 1)
                    {
                        // try a k-w bit table
                        // too few codes for k-w bit table
                        f -= (a + 1); // deduct codes from patterns left
                        xp = k;
                        if (j < z)
                        {
                            while (++j < z)
                            {
                                // try smaller tables up to z bits
                                if ((f <<= 1) <= c[++xp])
                                    break; // enough codes to use up j bits
                                f -= c[xp]; // else deduct codes from patterns
                            }
                        }
                    }
                    z = 1 << j; // table entries for j-bit table

                    // allocate new table
                    if (hn[0] + z > MANY)
                    {
                        // (note: doesn't matter for fixed)
                        return ZipResult.Z_DATA_ERROR; // overflow of MANY
                    }
                    u[h] = q = hn[0]; // DEBUG
                    hn[0] += z;

                    // connect to last table, if there is one
                    if (h != 0)
                    {
                        x[h] = i; // save pattern for backing up
                        r[0] = cast(byte)j; // bits in this table
                        r[1] = cast(byte)l; // bits to dump before this table
                        j = Tree.urShift(i, (w - l));
                        r[2] = cast(int)(q - u[h - 1] - j); // offset to this table
                        const hbStart = (u[h - 1] + j) * 3;
                        hp[hbStart..hbStart + 3] = r[0..3]; // connect to last table
                    }
                    else
                    {
                        t[0] = q; // first table is returned result
                    }
                }

                // set up table entry in r
                r[1] = cast(byte)(k - w);
                if (p >= n)
                {
                    r[0] = 128 + 64; // out of values--invalid code
                }
                else if (v[p] < s)
                {
                    r[0] = cast(byte)(v[p] < 256 ? 0 : (32 + 64)); // 256 is end-of-block
                    r[2] = v[p++]; // simple code is just the value
                }
                else
                {
                    r[0] = cast(byte)(e[v[p] - s] + 16 + 64); // non-simple--look up in lists
                    r[2] = d[v[p++] - s];
                }

                // fill code-like entries with r
                f = 1 << (k - w);
                for (j = Tree.urShift(i, w); j < z; j += f)
                {
                    const hpStart = (q + j) * 3;
                    hp[hpStart..hpStart + 3] = r[0..3];
                }

                // backwards increment the k-bit code i
                for (j = 1 << (k - 1); (i & j) != 0; j = Tree.urShift(j, 1))
                {
                    i ^= j;
                }
                i ^= j;

                // backup over finished tables
                mask = (1 << w) - 1; // needed on HP, cc -O bug
                while ((i & mask) != x[h])
                {
                    h--; // don't need to update q
                    w -= l;
                    mask = (1 << w) - 1;
                }
            }
        }
        // Return Z_BUF_ERROR if we were given an incomplete table
        return y != 0 && g != 1 ? ZipResult.Z_BUF_ERROR : ZipResult.Z_OK;
    }

    final void initWorkArea(int vsize)
    {
        hn.length = 1;
        c.length = BMAX + 1;
        r.length = 3;
        u.length = BMAX;
        x.length = BMAX + 1;
        if (v.length < vsize)
            v.length = vsize;
        v[] = 0;
        c[] = 0;
        r[] = 0;
        u[] = 0;
        x[] = 0;
    }

private:
    enum int MANY = 1440;
    enum int fixed_bl = 9;
    enum int fixed_bd = 5;

    // If BMAX needs to be larger than 16, then h and x[] should be uLong.
    enum BMAX = 15; // maximum bit length of any code

    //UPGRADE_NOTE: Final was removed from the declaration of 'fixed_tl'. "ms-help://MS.VSCC.v80/dv_commoner/local/redirect.htm?index='!DefaultContextWindowIndex'&keyword='jlca1003'"
    static immutable const(int)[] fixed_tl = [
        96, 7, 256, 0, 8, 80, 0, 8, 16, 84, 8, 115, 82, 7, 31, 0, 8, 112, 0, 8, 48, 0, 9, 192, 80, 7, 10, 0, 8, 96, 0, 8, 32, 0, 9, 160, 0, 8, 0, 0, 8, 128, 0, 8, 64, 0, 9, 224, 80, 7, 6, 0, 8, 88, 0, 8, 24, 0, 9, 144, 83, 7, 59, 0, 8, 120, 0, 8, 56, 0, 9, 208, 81, 7, 17, 0, 8, 104, 0, 8, 40, 0, 9, 176, 0, 8, 8, 0, 8, 136, 0, 8, 72, 0, 9, 240, 80, 7, 4, 0, 8, 84, 0, 8, 20, 85, 8, 227, 83, 7, 43, 0, 8, 116, 0, 8, 52, 0, 9, 200, 81, 7, 13, 0, 8, 100, 0, 8, 36, 0, 9, 168, 0, 8, 4, 0, 8, 132, 0, 8, 68, 0, 9, 232, 80, 7, 8, 0, 8, 92, 0, 8, 28, 0, 9, 152, 84, 7, 83, 0, 8, 124, 0, 8, 60, 0, 9, 216, 82, 7, 23, 0, 8, 108, 0, 8, 44, 0, 9, 184, 0, 8, 12, 0, 8, 140, 0, 8, 76, 0, 9, 248, 80, 7, 3, 0, 8, 82, 0, 8, 18, 85, 8, 163, 83, 7, 35, 0, 8, 114, 0, 8, 50, 0, 9, 196, 81, 7, 11, 0, 8, 98, 0, 8, 34, 0, 9, 164, 0, 8, 2, 0, 8, 130, 0, 8, 66, 0, 9, 228, 80, 7, 7, 0, 8, 90, 0, 8, 26, 0, 9, 148, 84, 7, 67, 0, 8, 122, 0, 8, 58, 0, 9, 212, 82, 7, 19, 0, 8, 106, 0, 8, 42, 0, 9, 180, 0, 8, 10, 0, 8, 138, 0, 8, 74, 0, 9, 244, 80, 7, 5, 0, 8, 86, 0, 8, 22, 192, 8, 0, 83, 7, 51, 0, 8, 118, 0, 8, 54, 0, 9, 204, 81, 7, 15, 0, 8, 102, 0, 8, 38, 0, 9, 172, 0, 8, 6, 0, 8, 134, 0, 8, 70, 0, 9, 236, 80, 7, 9, 0, 8, 94, 0, 8, 30, 0, 9, 156, 84, 7, 99, 0, 8, 126, 0, 8, 62, 0, 9, 220, 82, 7, 27, 0, 8, 110, 0, 8, 46, 0, 9, 188, 0, 8, 14, 0, 8, 142, 0, 8, 78, 0, 9, 252, 96, 7, 256, 0, 8, 81, 0, 8, 17, 85, 8, 131, 82, 7, 31, 0, 8, 113, 0, 8, 49, 0, 9, 194, 80, 7, 10, 0, 8, 97, 0, 8, 33, 0, 9, 162, 0, 8, 1, 0, 8, 129, 0, 8, 65, 0, 9, 226, 80, 7, 6, 0, 8, 89, 0, 8, 25, 0, 9, 146, 83, 7, 59, 0, 8, 121, 0, 8, 57, 0, 9, 210, 81, 7, 17, 0, 8, 105, 0, 8, 41, 0, 9, 178, 0, 8, 9, 0, 8, 137, 0, 8, 73, 0, 9, 242, 80, 7, 4, 0, 8, 85, 0, 8, 21, 80, 8, 258, 83, 7, 43, 0, 8, 117, 0, 8, 53, 0, 9, 202, 81, 7, 13, 0, 8, 101, 0, 8, 37, 0, 9, 170, 0, 8, 5, 0, 8, 133, 0, 8, 69, 0, 9, 234, 80, 7, 8, 0, 8, 93, 0, 8, 29, 0, 9, 154, 84, 7, 83, 0, 8, 125, 0, 8, 61, 0, 9, 218, 82, 7, 23, 0, 8, 109, 0, 8, 45, 0, 9, 186,
        0, 8, 13, 0, 8, 141, 0, 8, 77, 0, 9, 250, 80, 7, 3, 0, 8, 83, 0, 8, 19, 85, 8, 195, 83, 7, 35, 0, 8, 115, 0, 8, 51, 0, 9, 198, 81, 7, 11, 0, 8, 99, 0, 8, 35, 0, 9, 166, 0, 8, 3, 0, 8, 131, 0, 8, 67, 0, 9, 230, 80, 7, 7, 0, 8, 91, 0, 8, 27, 0, 9, 150, 84, 7, 67, 0, 8, 123, 0, 8, 59, 0, 9, 214, 82, 7, 19, 0, 8, 107, 0, 8, 43, 0, 9, 182, 0, 8, 11, 0, 8, 139, 0, 8, 75, 0, 9, 246, 80, 7, 5, 0, 8, 87, 0, 8, 23, 192, 8, 0, 83, 7, 51, 0, 8, 119, 0, 8, 55, 0, 9, 206, 81, 7, 15, 0, 8, 103, 0, 8, 39, 0, 9, 174, 0, 8, 7, 0, 8, 135, 0, 8, 71, 0, 9, 238, 80, 7, 9, 0, 8, 95, 0, 8, 31, 0, 9, 158, 84, 7, 99, 0, 8, 127, 0, 8, 63, 0, 9, 222, 82, 7, 27, 0, 8, 111, 0, 8, 47, 0, 9, 190, 0, 8, 15, 0, 8, 143, 0, 8, 79, 0, 9, 254, 96, 7, 256, 0, 8, 80, 0, 8, 16, 84, 8, 115, 82, 7, 31, 0, 8, 112, 0, 8, 48, 0, 9, 193, 80, 7, 10, 0, 8, 96, 0, 8, 32, 0, 9, 161, 0, 8, 0, 0, 8, 128, 0, 8, 64, 0, 9, 225, 80, 7, 6, 0, 8, 88, 0, 8, 24, 0, 9, 145, 83, 7, 59, 0, 8, 120, 0, 8, 56, 0, 9, 209, 81, 7, 17, 0, 8, 104, 0, 8, 40, 0, 9, 177, 0, 8, 8, 0, 8, 136, 0, 8, 72, 0, 9, 241, 80, 7, 4, 0, 8, 84, 0, 8, 20, 85, 8, 227, 83, 7, 43, 0, 8, 116, 0, 8, 52, 0, 9, 201, 81, 7, 13, 0, 8, 100, 0, 8, 36, 0, 9, 169, 0, 8, 4, 0, 8, 132, 0, 8, 68, 0, 9, 233, 80, 7, 8, 0, 8, 92, 0, 8, 28, 0, 9, 153, 84, 7, 83, 0, 8, 124, 0, 8, 60, 0, 9, 217, 82, 7, 23, 0, 8, 108, 0, 8, 44, 0, 9, 185, 0, 8, 12, 0, 8, 140, 0, 8, 76, 0, 9, 249, 80, 7, 3, 0, 8, 82, 0, 8, 18, 85, 8, 163, 83, 7, 35, 0, 8, 114, 0, 8, 50, 0, 9, 197, 81, 7, 11, 0, 8, 98, 0, 8, 34, 0, 9, 165, 0, 8, 2, 0, 8, 130, 0, 8, 66, 0, 9, 229, 80, 7, 7, 0, 8, 90, 0, 8, 26, 0, 9, 149, 84, 7, 67, 0, 8, 122, 0, 8, 58, 0, 9, 213, 82, 7, 19, 0, 8, 106, 0, 8, 42, 0, 9, 181, 0, 8, 10, 0, 8, 138, 0, 8, 74, 0, 9, 245, 80, 7, 5, 0, 8, 86, 0, 8, 22, 192, 8, 0, 83, 7, 51, 0, 8, 118, 0, 8, 54, 0, 9, 205, 81, 7, 15, 0, 8, 102, 0, 8, 38, 0, 9, 173, 0, 8, 6, 0, 8, 134, 0, 8, 70, 0, 9, 237, 80, 7, 9, 0, 8, 94, 0, 8, 30, 0, 9, 157, 84, 7, 99, 0, 8, 126, 0, 8, 62, 0, 9, 221, 82, 7, 27, 0, 8, 110, 0, 8, 46, 0, 9, 189, 0, 8,
        14, 0, 8, 142, 0, 8, 78, 0, 9, 253, 96, 7, 256, 0, 8, 81, 0, 8, 17, 85, 8, 131, 82, 7, 31, 0, 8, 113, 0, 8, 49, 0, 9, 195, 80, 7, 10, 0, 8, 97, 0, 8, 33, 0, 9, 163, 0, 8, 1, 0, 8, 129, 0, 8, 65, 0, 9, 227, 80, 7, 6, 0, 8, 89, 0, 8, 25, 0, 9, 147, 83, 7, 59, 0, 8, 121, 0, 8, 57, 0, 9, 211, 81, 7, 17, 0, 8, 105, 0, 8, 41, 0, 9, 179, 0, 8, 9, 0, 8, 137, 0, 8, 73, 0, 9, 243, 80, 7, 4, 0, 8, 85, 0, 8, 21, 80, 8, 258, 83, 7, 43, 0, 8, 117, 0, 8, 53, 0, 9, 203, 81, 7, 13, 0, 8, 101, 0, 8, 37, 0, 9, 171, 0, 8, 5, 0, 8, 133, 0, 8, 69, 0, 9, 235, 80, 7, 8, 0, 8, 93, 0, 8, 29, 0, 9, 155, 84, 7, 83, 0, 8, 125, 0, 8, 61, 0, 9, 219, 82, 7, 23, 0, 8, 109, 0, 8, 45, 0, 9, 187, 0, 8, 13, 0, 8, 141, 0, 8, 77, 0, 9, 251, 80, 7, 3, 0, 8, 83, 0, 8, 19, 85, 8, 195, 83, 7, 35, 0, 8, 115, 0, 8, 51, 0, 9, 199, 81, 7, 11, 0, 8, 99, 0, 8, 35, 0, 9, 167, 0, 8, 3, 0, 8, 131, 0, 8, 67, 0, 9, 231, 80, 7, 7, 0, 8, 91, 0, 8, 27, 0, 9, 151, 84, 7, 67, 0, 8, 123, 0, 8, 59, 0, 9, 215, 82, 7, 19, 0, 8, 107, 0, 8, 43, 0, 9, 183, 0, 8, 11, 0, 8, 139, 0, 8, 75, 0, 9, 247, 80, 7, 5, 0, 8, 87, 0, 8, 23, 192, 8, 0, 83, 7, 51, 0, 8, 119, 0, 8, 55, 0, 9, 207, 81, 7, 15, 0, 8, 103, 0, 8, 39, 0, 9, 175, 0, 8, 7, 0, 8, 135, 0, 8, 71, 0, 9, 239, 80, 7, 9, 0, 8, 95, 0, 8, 31, 0, 9, 159, 84, 7, 99, 0, 8, 127, 0, 8, 63, 0, 9, 223, 82, 7, 27, 0, 8, 111, 0, 8, 47, 0, 9, 191, 0, 8, 15, 0, 8, 143, 0, 8, 79, 0, 9, 255
        ];

    //UPGRADE_NOTE: Final was removed from the declaration of 'fixed_td'. "ms-help://MS.VSCC.v80/dv_commoner/local/redirect.htm?index='!DefaultContextWindowIndex'&keyword='jlca1003'"
    static immutable const(int)[] fixed_td = [
        80, 5, 1, 87, 5, 257, 83, 5, 17, 91, 5, 4097, 81, 5, 5, 89, 5, 1025, 85, 5, 65, 93, 5, 16385, 80, 5, 3, 88, 5, 513, 84, 5, 33, 92, 5, 8193, 82, 5, 9, 90, 5, 2049, 86, 5, 129, 192, 5, 24577, 80, 5, 2, 87, 5, 385, 83, 5, 25, 91, 5, 6145, 81, 5, 7, 89, 5, 1537, 85, 5, 97, 93, 5, 24577, 80, 5, 4, 88, 5, 769, 84, 5, 49, 92, 5, 12289, 82, 5, 13, 90, 5, 3073, 86, 5, 193, 192, 5, 24577
        ];

    // Tables for deflate from PKZIP's appnote.txt.
    //UPGRADE_NOTE: Final was removed from the declaration of 'cplens'. "ms-help://MS.VSCC.v80/dv_commoner/local/redirect.htm?index='!DefaultContextWindowIndex'&keyword='jlca1003'"
    static immutable const(int)[] cplens = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258, 0, 0
        ];

    // see note #13 above about 258
    //UPGRADE_NOTE: Final was removed from the declaration of 'cplext'. "ms-help://MS.VSCC.v80/dv_commoner/local/redirect.htm?index='!DefaultContextWindowIndex'&keyword='jlca1003'"
    static immutable const(int)[] cplext = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0, 112, 112
        ];

    //UPGRADE_NOTE: Final was removed from the declaration of 'cpdist'. "ms-help://MS.VSCC.v80/dv_commoner/local/redirect.htm?index='!DefaultContextWindowIndex'&keyword='jlca1003'"
    static immutable const(int)[] cpdist = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
        ];

    //UPGRADE_NOTE: Final was removed from the declaration of 'cpdext'. "ms-help://MS.VSCC.v80/dv_commoner/local/redirect.htm?index='!DefaultContextWindowIndex'&keyword='jlca1003'"
    static immutable const(int)[] cpdext = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
        ];

    int[] hn; // hufts used in space
    int[] v; // work area for huft_build
    int[] c; // bit length count table
    int[] r; // table entry for structure assignment
    int[] u; // table stack
    int[] x; // bit offsets, then code stack
}

class StaticTree
{
nothrow @safe:

public:
    this(const(short)[] treeCodes, const(int)[] extraBits, int extraBase, int elems, int maxLength)
    {
        this.treeCodes = treeCodes;
        this.extraBits = extraBits;
        this.extraBase = extraBase;
        this.elems = elems;
        this.maxLength = maxLength;
    }

public:
    static immutable const(short)[] distTreeCodes = [
        0, 5, 16, 5, 8, 5, 24, 5, 4, 5, 20, 5, 12, 5, 28, 5,
        2, 5, 18, 5, 10, 5, 26, 5, 6, 5, 22, 5, 14, 5, 30, 5,
        1, 5, 17, 5, 9, 5, 25, 5, 5, 5, 21, 5, 13, 5, 29, 5,
        3, 5, 19, 5, 11, 5, 27, 5, 7, 5, 23, 5
        ];

    static immutable const(short)[] lengthAndLiteralsTreeCodes = [
        12, 8, 140, 8, 76, 8, 204, 8, 44, 8, 172, 8, 108, 8, 236, 8,
        28, 8, 156, 8, 92, 8, 220, 8, 60, 8, 188, 8, 124, 8, 252, 8,
         2, 8, 130, 8, 66, 8, 194, 8, 34, 8, 162, 8, 98, 8, 226, 8,
        18, 8, 146, 8, 82, 8, 210, 8, 50, 8, 178, 8, 114, 8, 242, 8,
        10, 8, 138, 8, 74, 8, 202, 8, 42, 8, 170, 8, 106, 8, 234, 8,
        26, 8, 154, 8, 90, 8, 218, 8, 58, 8, 186, 8, 122, 8, 250, 8,
         6, 8, 134, 8, 70, 8, 198, 8, 38, 8, 166, 8, 102, 8, 230, 8,
        22, 8, 150, 8, 86, 8, 214, 8, 54, 8, 182, 8, 118, 8, 246, 8,
        14, 8, 142, 8, 78, 8, 206, 8, 46, 8, 174, 8, 110, 8, 238, 8,
        30, 8, 158, 8, 94, 8, 222, 8, 62, 8, 190, 8, 126, 8, 254, 8,
         1, 8, 129, 8, 65, 8, 193, 8, 33, 8, 161, 8, 97, 8, 225, 8,
        17, 8, 145, 8, 81, 8, 209, 8, 49, 8, 177, 8, 113, 8, 241, 8,
         9, 8, 137, 8, 73, 8, 201, 8, 41, 8, 169, 8, 105, 8, 233, 8,
        25, 8, 153, 8, 89, 8, 217, 8, 57, 8, 185, 8, 121, 8, 249, 8,
         5, 8, 133, 8, 69, 8, 197, 8, 37, 8, 165, 8, 101, 8, 229, 8,
        21, 8, 149, 8, 85, 8, 213, 8, 53, 8, 181, 8, 117, 8, 245, 8,
        13, 8, 141, 8, 77, 8, 205, 8, 45, 8, 173, 8, 109, 8, 237, 8,
        29, 8, 157, 8, 93, 8, 221, 8, 61, 8, 189, 8, 125, 8, 253, 8,
        19, 9, 275, 9, 147, 9, 403, 9, 83, 9, 339, 9, 211, 9, 467, 9,
        51, 9, 307, 9, 179, 9, 435, 9, 115, 9, 371, 9, 243, 9, 499, 9,
        11, 9, 267, 9, 139, 9, 395, 9, 75, 9, 331, 9, 203, 9, 459, 9,
        43, 9, 299, 9, 171, 9, 427, 9, 107, 9, 363, 9, 235, 9, 491, 9,
        27, 9, 283, 9, 155, 9, 411, 9, 91, 9, 347, 9, 219, 9, 475, 9,
        59, 9, 315, 9, 187, 9, 443, 9, 123, 9, 379, 9, 251, 9, 507, 9,
         7, 9, 263, 9, 135, 9, 391, 9, 71, 9, 327, 9, 199, 9, 455, 9,
        39, 9, 295, 9, 167, 9, 423, 9, 103, 9, 359, 9, 231, 9, 487, 9,
        23, 9, 279, 9, 151, 9, 407, 9, 87, 9, 343, 9, 215, 9, 471, 9,
        55, 9, 311, 9, 183, 9, 439, 9, 119, 9, 375, 9, 247, 9, 503, 9,
        15, 9, 271, 9, 143, 9, 399, 9, 79, 9, 335, 9, 207, 9, 463, 9,
        47, 9, 303, 9, 175, 9, 431, 9, 111, 9, 367, 9, 239, 9, 495, 9,
        31, 9, 287, 9, 159, 9, 415, 9, 95, 9, 351, 9, 223, 9, 479, 9,
        63, 9, 319, 9, 191, 9, 447, 9, 127, 9, 383, 9, 255, 9, 511, 9,
         0, 7, 64, 7, 32, 7, 96, 7, 16, 7, 80, 7, 48, 7, 112, 7,
         8, 7, 72, 7, 40, 7, 104, 7, 24, 7, 88, 7, 56, 7, 120, 7,
         4, 7, 68, 7, 36, 7, 100, 7, 20, 7, 84, 7, 52, 7, 116, 7,
         3, 8, 131, 8, 67, 8, 195, 8, 35, 8, 163, 8, 99, 8, 227, 8
        ];

    const(short)[] treeCodes; // static tree or null
    const(int)[] extraBits;   // extra bits for each code or null
    const int extraBase;     // base index for extra_bits
    const int elems;         // max number of elements in the tree
    const int maxLength;     // max bit length for the codes

    static StaticTree Literals;
    static StaticTree Distances;
    static StaticTree BitLengths;

private:
    static this()
    {
        Literals = new StaticTree(lengthAndLiteralsTreeCodes, Tree.ExtraLengthBits, ZipConst.LITERALS + 1, ZipConst.L_CODES, ZipConst.MAX_BITS);
        Distances = new StaticTree(distTreeCodes, Tree.ExtraDistanceBits, 0, ZipConst.D_CODES, ZipConst.MAX_BITS);
        BitLengths = new StaticTree(null, Tree.extra_blbits, 0, ZipConst.BL_CODES, ZipConst.MAX_BL_BITS);
    }
}
