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

module pham.db.db_pgauth;

public import pham.cp.cp_cipher : CipherBuffer;
import pham.db.db_auth;
import pham.db.db_type : DbScheme;

nothrow @safe:

abstract class PgAuth : DbAuth
{
nothrow @safe:

public:
    static DbAuthMap findAuthMap(scope const(char)[] name)
    {
        return DbAuth.findAuthMap(name, DbScheme.pg);
    }

    @property final override DbScheme scheme() const pure
    {
        return DbScheme.pg;
    }
}
