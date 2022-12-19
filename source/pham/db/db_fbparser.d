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

module pham.db.fbparser;

import pham.utl.numeric_parser : NumericParsedKind, parseIntegral;
import pham.utl.result : ResultIf;
import pham.db.parser;
import pham.db.fbtype;

nothrow @safe:

/**
 * CREATE {DATABASE | SCHEMA} '<filespec>'
 * [USER user-name [PASSWORD 'password']]
 * [ROLE role-name]
 * [PAGE_SIZE [=] int]
 * [DEFAULT CHARACTER SET charset-name [COLLATION collation-name]]
 * [FORCED_WRITE [=] int]
 * [OVER_WRITE [=] int]
 * [LENGTH [=] int [PAGE[S]]]  -- Ignore
 * [<secondary_file>]  -- Ignore
 */
ResultIf!FbCreateDatabaseInfo parseCreateDatabase(string createDatabaseStatement)
{    
    static immutable string sqlKind = "CREATE";
    
    enum LiteralKeyword : ubyte
    {
        //create,
        user,
        //password,
        role,
        pageSize,
        default_,
        //character,
        //set,
        //collation,
        //length,
        //page,
        //pages,
        forcedWrite,
        overwrite,
        unknown,
    }

    auto tokenizer = DbTokenizer!(string, DbTokenSkipLevel.spaceLine)(createDatabaseStatement);
    ResultIf!FbCreateDatabaseInfo result = ResultIf!FbCreateDatabaseInfo.ok(FbCreateDatabaseInfo.init);

    string[15] alreadyProcessed;
    uint alreadyProcessedI;

    LiteralKeyword currentKeyword()
    {            
        if (tokenizer.kind != DbTokenKind.literal)
        {
            tokenizer.popFront();
            return LiteralKeyword.unknown;
        }
        
        auto s = tokenizer.front;
        tokenizer.popFront();
        LiteralKeyword result;
            
        //if (sicmp("CREATE", s) == 0)
        //    return LiteralKeyword.create;
        if (sicmp("USER", s) == 0)
            result = LiteralKeyword.user;
        //else if (sicmp("PASSWORD", s) == 0)
        //    return LiteralKeyword.password;
        else if (sicmp("ROLE", s) == 0)
            result = LiteralKeyword.role;
        else if (sicmp("PAGE_SIZE", s) == 0)
            result = LiteralKeyword.pageSize;
        else if (sicmp("DEFAULT", s) == 0)
            result = LiteralKeyword.default_;
        //else if (sicmp("CHARACTER", s) == 0)
        //    result = LiteralKeyword.character;
        //else if (sicmp("SET", s) == 0)
        //    result = LiteralKeyword.set;
        //else if (sicmp("COLLATION", s) == 0)
        //    result = LiteralKeyword.collation;
        //else if (sicmp("LENGTH", s) == 0)
        //    result = LiteralKeyword.length;
        //else if (sicmp("PAGE", s) == 0)
        //    result = LiteralKeyword.page;
        //else if (sicmp("PAGES", s) == 0)
        //    result = LiteralKeyword.pages;
        else if (sicmp("FORCED_WRITE", s) == 0)
            result = LiteralKeyword.forcedWrite;
        else if (sicmp("OVER_WRITE", s) == 0)
            result = LiteralKeyword.overwrite;
        else
            return LiteralKeyword.unknown;
            
        alreadyProcessed[alreadyProcessedI++] = s;
        return result;
    }
    
    int expectKeyword(string keyword1, string orKeyword2 = null)
    {
        if (tokenizer.empty)
        {
            result = DbTokenErrorMessage.eosResult!FbCreateDatabaseInfo(sqlKind);
            return 0;
        }

        if (tokenizer.kind != DbTokenKind.literal)
        {
            result = DbTokenErrorMessage.keywordResult!FbCreateDatabaseInfo(sqlKind, keyword1, tokenizer.front);
            return 0;
        }

        if (sicmp(keyword1, tokenizer.front) == 0)
        {
            tokenizer.popFront();
            return 1;
        }
        
        if (orKeyword2.length != 0 && sicmp(orKeyword2, tokenizer.front) == 0)
        {
            result = DbTokenErrorMessage.keywordResult!FbCreateDatabaseInfo(sqlKind, keyword1, tokenizer.front);
            return 2;
        }

        return 0;
    }

    bool expectKind(scope const(DbTokenKind)[] kinds, string tokenMessage, ref string value, string optionalSeparatorLiteral = null)
    {
        if (optionalSeparatorLiteral.length != 0
            && tokenizer.kind == DbTokenKind.literal
            && sicmp(tokenizer.front, optionalSeparatorLiteral) == 0)
            tokenizer.popFront();

        if (tokenizer.empty)
        {
            result = DbTokenErrorMessage.eosResult!FbCreateDatabaseInfo(sqlKind);
            return false;
        }

        if (tokenizer.isCurrentKind(kinds) < 0)
        {
            result = DbTokenErrorMessage.otherResult!FbCreateDatabaseInfo(sqlKind, tokenMessage, tokenizer.front);
            return false;
        }

        value = tokenizer.front;
        tokenizer.popFront();
        return true;
    }

    bool expectKindInt(string tokenMessage, ref int value, string optionalSeparatorLiteral = null)
    {
        string sValue;
        bool valid = expectKind([DbTokenKind.literal], tokenMessage, sValue, optionalSeparatorLiteral);
        if (valid)
        {
            valid = parseIntegral!(string, int)(sValue, value) == NumericParsedKind.ok;
            if (!valid)
                result = ResultIf!FbCreateDatabaseInfo.error(DbErrorCode.parse, DbTokenErrorMessage.conversion(sqlKind, sValue, "int"));
        }
        return valid;
    }

    bool expectKindName(string tokenMessage, ref string value, string optionalSeparatorLiteral = null)
    {
        bool valid = expectKind([DbTokenKind.literal, DbTokenKind.quotedSingle, DbTokenKind.quotedDouble], tokenMessage, value, optionalSeparatorLiteral);
        if (valid)
            value = tokenizer.removeQuoteIf(value);
        return valid;
    }

    bool expectKindQuoteString(string tokenMessage, ref string value, string optionalSeparatorLiteral = null)
    {
        bool valid = expectKind([DbTokenKind.quotedSingle, DbTokenKind.quotedDouble], tokenMessage, value, optionalSeparatorLiteral);
        if (valid)
            value = tokenizer.removeQuoteIf(value);
        return valid;
    }

    bool isAlreadyProcessed()
    {
        foreach (s; alreadyProcessed[0..alreadyProcessedI])
        {
            if (sicmp(s, tokenizer.front) == 0)
            {
                result = DbTokenErrorMessage.reKeywordResult!FbCreateDatabaseInfo(sqlKind, s);
                return true;
            }
        }
        return false;
    }

    bool isKind(scope const(DbTokenKind)[] kinds, string value)
    {
        if (tokenizer.isCurrentKind(kinds) >= 0 && sicmp(value, tokenizer.front) == 0)
        {
            tokenizer.popFront();
            return true;
        }
        else
            return false;
    }

    if (!expectKeyword("CREATE"))
        return result;
    if (!expectKeyword("DATABASE", "SCHEMA"))
        return result;
    if (!expectKindQuoteString("<filespec>", result.fileName))
        return result;
    alreadyProcessed[alreadyProcessedI++] = "CREATE";

    while (!tokenizer.empty)
    {
        if (tokenizer.kind == DbTokenKind.literal && isAlreadyProcessed())
            return result;

        final switch (currentKeyword())
        {
            case LiteralKeyword.user:
                if (!expectKindName("user-name", result.ownerName))
                    return result;
                if (isKind([DbTokenKind.literal], "PASSWORD"))
                {
                    if (!expectKindQuoteString("password", result.ownerPassword))
                        return result;
                    alreadyProcessed[alreadyProcessedI++] = "PASSWORD";
                }
                break;
            case LiteralKeyword.role:
                if (!expectKindName("role-name", result.roleName))
                    return result;
                break;
            case LiteralKeyword.pageSize:
                if (!expectKindInt("PAGE_SIZE int", result.pageSize, "="))
                    return result;
                break;
            case LiteralKeyword.default_:
                if (!expectKeyword("CHARACTER"))
                    return result;
                if (!expectKeyword("SET"))
                    return result;
                if (!expectKindName("CHARACTER SET name", result.defaultCharacterSet))
                    return result;
                if (isKind([DbTokenKind.literal], "COLLATION"))
                {
                    if (!expectKindName("COLLATION name", result.defaultCollation))
                        return result;
                    alreadyProcessed[alreadyProcessedI++] = "COLLATION";
                }
                break;
            case LiteralKeyword.forcedWrite:
                int tempInt;
                if (!expectKindInt("FORCED_WRITE int", tempInt, "="))
                    return result;
                result.forcedWrite = tempInt != 0;
                break;
            case LiteralKeyword.overwrite:
                int tempInt;
                if (!expectKindInt("OVER_WRITE int", tempInt, "="))
                    return result;
                result.overwrite = tempInt != 0;
                break;
            case LiteralKeyword.unknown:
                break;
        }
    }
    return result;
}


private:

unittest // parseCreateDatabase
{
    import pham.utl.test;
    traceUnitTest!("pham.db.fbdatabase")("unittest pham.db.fbparser.parseCreateDatabase");

    static immutable createSQL = q"SQL
CREATE DATABASE '\\Test\Firebird.fdb'
  USER sysdba PASSWORD 'masterkey'
  ROLE role_name
  PAGE_SIZE 8000
  DEFAULT CHARACTER SET char_set_name COLLATION collation_name
  FORCED_WRITE 1
  OVER_WRITE 1
SQL";

    auto validInfo = parseCreateDatabase(createSQL);
    assert(validInfo.isOK);
    assert(validInfo.fileName == "\\\\Test\\Firebird.fdb");
    assert(validInfo.defaultCharacterSet == "char_set_name");
    assert(validInfo.defaultCollation == "collation_name");
    assert(validInfo.ownerName == "sysdba");
    assert(validInfo.ownerPassword == "masterkey");
    assert(validInfo.roleName == "role_name");
    assert(validInfo.pageSize == 8000);
    assert(validInfo.forcedWrite);
    assert(validInfo.overwrite);


    auto failInfo = parseCreateDatabase(q"SQL
CREATE '\\Test\Firebird.fdb'
SQL");
    assert(failInfo.isError);

    failInfo = parseCreateDatabase(q"SQL
CREATE DATABASE
  PAGE_SIZE 8000
SQL");
    assert(failInfo.isError);

    failInfo = parseCreateDatabase(q"SQL
CREATE DATABASE '\\Test\Firebird.fdb'
  USER
SQL");
    assert(failInfo.isError);

    failInfo = parseCreateDatabase(q"SQL
CREATE DATABASE '\\Test\Firebird.fdb'
  ROLE
SQL");
    assert(failInfo.isError);

    failInfo = parseCreateDatabase(q"SQL
CREATE DATABASE '\\Test\Firebird.fdb'
  PAGE_SIZE n999
SQL");
    assert(failInfo.isError);

    failInfo = parseCreateDatabase(q"SQL
CREATE DATABASE '\\Test\Firebird.fdb'
  FORCED_WRITE n
SQL");
    assert(failInfo.isError);

    failInfo = parseCreateDatabase(q"SQL
CREATE DATABASE '\\Test\Firebird.fdb'
  OVER_WRITE n
SQL");
    assert(failInfo.isError);
}
