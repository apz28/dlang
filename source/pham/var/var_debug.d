/*
 *
 * License: $(HTTP www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * Authors: An Pham
 *
 * Copyright An Pham 2026 - xxxx.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE.txt or copy at http://www.boost.org/LICENSE_1_0.txt)
 *
*/

module pham.var.var_debug;

int debugVariantHandler;

void writeln(S...)(S args)
{
    import std.stdio : stdout, write;

    debug write(args, '\n');
    debug stdout.flush();
}

void writelnIf(S...)(S args)
{
    if (debugVariantHandler)
        writeln(args);
}
