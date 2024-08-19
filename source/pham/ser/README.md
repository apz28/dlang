Samples

    enum UnitTestEnum
    {
        first,
        second,
        third,
        forth,
        fifth,
        sixth,
    }

    @Serializable(null, null, DbEntity("UnitTestS1"))
    static struct UnitTestS1
    {
    public:
        @Serializable("publicInt", null, DbEntity("publicInt", DbKey.primary))
        int publicInt;

        private int _publicGetSet;

        int publicGetSet()
        {
            return _publicGetSet;
        }

        int publicGetSet(int i)
        {
            _publicGetSet = i;
            return i;
        }

        int publicOnlyGet()
        {
            return int.min;
        }

        int publicOnlySet(int i)
        {
            return int.max;
        }

        ref typeof(this) setValues() return
        {
            _publicGetSet = 1;
            publicInt = 20;
            return this;
        }

        void assertValues()
        {
            assert(publicGetSet == 1, _publicGetSet.to!string);
            assert(_protectedGetSet == 3, _protectedGetSet.to!string);
            assert(_privateGetSet == 5, _privateGetSet.to!string);
            assert(publicInt == 20, publicInt.to!string);
            assert(protectedInt == 0, protectedInt.to!string);
            assert(privateInt == 0, privateInt.to!string);
        }

        void assertValuesArray(int index)
        {
            assert(publicGetSet == 1+index, publicGetSet.to!string);
            assert(_protectedGetSet == 3, _protectedGetSet.to!string);
            assert(_privateGetSet == 5, _privateGetSet.to!string);
            assert(publicInt == 20+index, publicInt.to!string);
            assert(protectedInt == 0, protectedInt.to!string);
            assert(privateInt == 0, privateInt.to!string);
        }

    protected:
        int protectedInt = 0;
        int _protectedGetSet = 3;

        int protectedGetSet()
        {
            return _protectedGetSet;
        }

        int protectedGetSet(int i)
        {
            _protectedGetSet = i;
            return i;
        }

    private:
        int privateInt = 0;
        int _privateGetSet = 5;

        int privateGetSet()
        {
            return _privateGetSet;
        }

        int privateGetSet(int i)
        {
            _privateGetSet = i;
            return i;
        }
    }

    static class UnitTestC1
    {
    public:
        @Serializable("Int")
        int publicInt;

        private int _publicGetSet;
        UnitTestS1 publicStruct;

        @Serializable("GetSet")
        int publicGetSet()
        {
            return _publicGetSet;
        }

        int publicGetSet(int i)
        {
            _publicGetSet = i;
            return i;
        }

        int publicOnlyGet()
        {
            return int.min;
        }

        int publicOnlySet(int i)
        {
            return int.max;
        }

        UnitTestC1 setValues()
        {
            _publicGetSet = 1;
            publicInt = 30;
            publicStruct.setValues();
            return this;
        }

        void assertValues()
        {
            assert(_publicGetSet == 1, _publicGetSet.to!string);
            assert(_protectedGetSet == 3, _protectedGetSet.to!string);
            assert(_privateGetSet == 5, _privateGetSet.to!string);
            assert(publicInt == 30, publicInt.to!string);
            publicStruct.assertValues();
            assert(protectedInt == 0, protectedInt.to!string);
            assert(privateInt == 0, privateInt.to!string);
        }

    protected:
        int protectedInt = 0;
        int _protectedGetSet = 3;

        int protectedGetSet()
        {
            return _protectedGetSet;
        }

        int protectedGetSet(int i)
        {
            _protectedGetSet = i;
            return i;
        }

    private:
        int privateInt = 0;
        int _privateGetSet = 5;

        int privateGetSet()
        {
            return _privateGetSet;
        }

        int privateGetSet(int i)
        {
            _privateGetSet = i;
            return i;
        }
    }

    class UnitTestC2 : UnitTestC1
    {
    public:
        string publicStr;

        override int publicGetSet()
        {
            return _publicGetSet;
        }

        override UnitTestC2 setValues()
        {
            super.setValues();
            publicStr = "C2 public string";
            return this;
        }

        override void assertValues()
        {
            super.assertValues();
            assert(publicStr == "C2 public string", publicStr);
        }
    }

    class UnitTestAllTypes
    {
    public:
        UnitTestEnum enum1;
        bool bool1;
        byte byte1;
        ubyte ubyte1;
        short short1;
        ushort ushort1;
        int int1;
        uint uint1;
        long long1;
        ulong ulong1;
        float float1;
        float floatNaN;
        double double1;
        double doubleInf;
        string string1;
        char[] charArray;
        ubyte[] binary1;
        int[] intArray;
        int[] intArrayNull;
        int[int] intInt;
        int[int] intIntNull;
        UnitTestEnum[UnitTestEnum] enumEnum;
        string[string] strStr;
        UnitTestS1 struct1;
        UnitTestC1 class1;
        UnitTestC1 class1Null;

        typeof(this) setValues()
        {
            enum1 = UnitTestEnum.third;
            bool1 = true;
            byte1 = 101;
            short1 = -1003;
            ushort1 = 3975;
            int1 = -382653;
            uint1 = 3957209;
            long1 = -394572364;
            ulong1 = 284659274;
            float1 = 6394763.5;
            floatNaN = float.nan;
            double1 = -2846627456445.765;
            doubleInf = double.infinity;
            string1 = "test string of";
            charArray = "will this work?".dup;
            binary1 = [37,24,204,101,43];
            intArray = [135,937,3725,3068,38465,380];
            intArrayNull = null;
            intInt[2] = 23456;
            intInt[11] = 113456;
            intIntNull = null;
            enumEnum[UnitTestEnum.third] = UnitTestEnum.second;
            enumEnum[UnitTestEnum.forth] = UnitTestEnum.sixth;
            strStr["key1"] = "key1 value";
            strStr["key2"] = "key2 value";
            strStr["key3"] = null;
            struct1.setValues();
            class1 = new UnitTestC1();
            class1.setValues();
            class1Null = null;
            return this;
        }

        void assertValues()
        {
            import std.math : isInfinity, isNaN;

            assert(enum1 == UnitTestEnum.third, enum1.to!string);
            assert(bool1 == true, bool1.to!string);
            assert(byte1 == 101, byte1.to!string);
            assert(short1 == -1003, short1.to!string);
            assert(ushort1 == 3975, ushort1.to!string);
            assert(int1 == -382653, int1.to!string);
            assert(uint1 == 3957209, uint1.to!string);
            assert(long1 == -394572364, long1.to!string);
            assert(ulong1 == 284659274, ulong1.to!string);
            assert(float1 == 6394763.5, float1.to!string);
            assert(floatNaN.isNaN, floatNaN.to!string);
            assert(double1 == -2846627456445.765, double1.to!string);
            assert(doubleInf.isInfinity, doubleInf.to!string);
            assert(string1 == "test string of", string1);
            assert(charArray == "will this work?", charArray);
            assert(binary1 == [37,24,204,101,43], binary1.to!string);
            assert(intArray == [135,937,3725,3068,38465,380], intArray.to!string);
            assert(intArrayNull is null);
            assert(intInt[2] == 23456, intInt[2].to!string);
            assert(intInt[11] == 113456, intInt[11].to!string);
            assert(intIntNull is null);
            assert(enumEnum[UnitTestEnum.third] == UnitTestEnum.second, enumEnum[UnitTestEnum.third].to!string);
            assert(enumEnum[UnitTestEnum.forth] == UnitTestEnum.sixth, enumEnum[UnitTestEnum.forth].to!string);
            assert(strStr["key1"] == "key1 value", strStr["key1"]);
            assert(strStr["key2"] == "key2 value", strStr["key2"]);
            assert(strStr["key3"] is null, strStr["key3"]);
            struct1.assertValues();
            assert(class1 !is null);
            class1.assertValues();
            assert(class1Null is null);
        }
    }


JSON format
    static immutable string jsonUnitTestAllTypes =
        q"<{"enum1":"third","bool1":true,"byte1":101,"ubyte1":0,"short1":-1003,"ushort1":3975,"int1":-382653,"uint1":3957209,"long1":-394572364,"ulong1":284659274,"float1":6394763.5,"floatNaN":"NaN","double1":-2846627456445.7651,"doubleInf":"-Infinity","string1":"test string of","charArray":"will this work?","binary1":"JRjMZSs=","intArray":[135,937,3725,3068,38465,380],"intArrayNull":[],"intInt":{"2":23456,"11":113456},"intIntNull":null,"enumEnum":{"forth":"sixth","third":"second"},"strStr":{"key1":"key1 value","key2":"key2 value","key3":null},"struct1":{"publicInt":20,"publicGetSet":1},"class1":{"Int":30,"publicStruct":{"publicInt":20,"publicGetSet":1},"GetSet":1},"class1Null":null}>";

    {
        auto c = new UnitTestAllTypes();
        scope serializer = new JsonSerializer();
        serializer.serialize!UnitTestAllTypes(c.setValues());
        assert(serializer.buffer[] == jsonUnitTestAllTypes, serializer.buffer[]);
    }

    {
        scope deserializer = new JsonDeserializer(jsonUnitTestAllTypes);
        auto c = deserializer.deserialize!UnitTestAllTypes();
        assert(c !is null);
        c.assertValues();
    }


Binary format
    import pham.utl.utl_object : bytesFromHexs, bytesToHexs;
    static immutable string binUnitTestAllTypes =
        "5048414D000116401205656E756D31110574686972641205626F6F6C31020112056279746531066512067562797465310600120673686F72743107EA0F12077573686F72743107873E1204696E743108FCDA2E120575696E7431089987E30312056C6F6E673109CBC9A5F8021206756C6F6E6731098AB9BC8F021206666C6F6174310C979C99AC091208666C6F61744E614E0C808080FC0F1207646F75626C65310D9FB8EFF2B790DB8485031209646F75626C65496E660D80808080808080F0FF011207737472696E6731110E7465737420737472696E67206F661209636861724172726179110F77696C6C207468697320776F726B3F120762696E6172793115052518CC652B1208696E744172726179180608870208A90E088D3A08BC2F0881D90408BC0519120C696E7441727261794E756C6C1800191206696E74496E74160212013208A0EE021202313108B0EC0D17120A696E74496E744E756C6C1600171208656E756D456E756D16021205666F727468110573697874681205746869726411067365636F6E64171206737472537472160312046B657931110A6B6579312076616C756512046B657932110A6B6579322076616C756512046B657933110017120773747275637431164012097075626C6963496E740814120C7075626C69634765745365740801171206636C6173733116401203496E74081E120C7075626C6963537472756374164012097075626C6963496E740814120C7075626C69634765745365740801171206476574536574080117120A636C617373314E756C6C16001717";

    {
        auto c = new UnitTestAllTypes();
        scope serializer = new BinarySerializer();
        serializer.serialize!UnitTestAllTypes(c.setValues());
        assert(bytesToHexs(serializer.buffer[]) == binUnitTestAllTypes, bytesToHexs(serializer.buffer[]));
    }

    {
        scope deserializer = new BinaryDeserializer(bytesFromHexs(binUnitTestAllTypes));
        auto c = deserializer.deserialize!UnitTestAllTypes();
        assert(c !is null);
        c.assertValues();
    }


Database
    import pham.db.db_database : DbConnection, DbDatabaseList;
    import pham.db.db_type;
    import pham.db.db_fbdatabase;

    DbConnection createUnitTestConnection(
        DbEncryptedConnection encrypt = DbEncryptedConnection.disabled,
        DbCompressConnection compress = DbCompressConnection.disabled,
        DbIntegratedSecurityConnection integratedSecurity = DbIntegratedSecurityConnection.srp256)
    {
        auto db = DbDatabaseList.getDb(DbScheme.fb);
        auto result = db.createConnection(""); // Or simply result = new FbConnection(null);
        auto csb = result.connectionStringBuilder;
        csb.databaseName = "UNIT_TEST";  // Use alias mapping name
	csb.userName = "SYSDBA";
	csb.userPassword = "masterkey";
        csb.receiveTimeout = dur!"seconds"(40);
        csb.sendTimeout = dur!"seconds"(20);
        csb.encrypt = encrypt;
        csb.compress = compress;
        csb.integratedSecurity = integratedSecurity;
        return result;
    }

    struct UnitTestCaptureSQL
    {
        string commandText;
        DbRecordsAffected commandResult;
        DbSerializerCommandQuery commandQuery;
        bool logOnly;

        DbRecordsAffected execute(DbSerializer serializer,
            DbSerializerCommandQuery commandQuery, ref Appender!string commandText, DbParameterList commandParameters,
            scope ref Serializable attribute) @safe
        {
            this.commandQuery = commandQuery;
            this.commandText = commandText[];

            debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(commandQuery=", commandQuery, ", commandText=", commandText, ")");

            this.commandResult = logOnly
                ? DbRecordsAffected.init
                : serializer.connection.executeNonQuery(this.commandText, commandParameters);
            return this.commandResult;
        }

        DbReader select(DbDeserializer serializer,
            ref Appender!string commandText, DbParameterList conditionParameters,
            scope ref Serializable attribute) @safe
        {
            this.commandText = commandText[];

            debug(pham_ser_ser_serialization_db) debug writeln(__FUNCTION__, "(commandText=", commandText, ")");

            return logOnly
                ? DbReader.init
                : serializer.connection.executeReader(this.commandText, conditionParameters);
        }
    }
    
    auto connection = createUnitTestConnection();
    scope (exit)
        connection.dispose();
    connection.open();

    connection.createTableOrEmpty("UnitTestS1",
        "CREATE TABLE UnitTestS1(publicInt INTEGER NOT NULL PRIMARY KEY, publicGetSet INTEGER)");
    scope (exit)
        connection.executeNonQuery("DROP TABLE UnitTestS1");

    {
        auto c = UnitTestS1();
        scope serializer = new DbSerializer(connection);
        serializer.onExecuteSQL = &captureSQL.execute;

	// insert
        serializer.insert!UnitTestS1(c.setValues());
        debug(pham_ser_ser_serialization_db) debug writeln("insert!UnitTestS1=", captureSQL.commandQuery, ", commandText=", captureSQL.commandText,
            ", commandResult=", captureSQL.commandResult);
        assert(captureSQL.logOnly || captureSQL.commandResult == 1);

	// update
        serializer.update!UnitTestS1(c.setValues());
        debug(pham_ser_ser_serialization_db) debug writeln("update!UnitTestS1=", captureSQL.commandQuery, ", commandText=", captureSQL.commandText,
            ", commandResult=", captureSQL.commandResult);
        assert(captureSQL.logOnly || captureSQL.commandResult >= 0); // If INSERT not in tranaction, it mays not updating any record
    }

    // One struct with manual sql reader
    {
        auto reader = connection.executeReader("SELECT publicInt, publicGetSet FROM UnitTestS1");
        scope deserializer = new DbDeserializer(&reader);
        auto c = deserializer.deserialize!UnitTestS1();
        c.assertValues();
    }

    // One struct with sql select
    {
        scope deserializer = new DbDeserializer(connection);
        auto c = deserializer.select!UnitTestS1(["publicInt":Variant(20)]);
        c.assertValues();
    }

    // Array of structs
    {
        connection.executeNonQuery("INSERT INTO UnitTestS1(publicInt, publicGetSet) VALUES(21, 2)");
        auto reader = connection.executeReader("SELECT publicInt, publicGetSet FROM UnitTestS1 ORDER BY publicInt");
        scope deserializer = new DbDeserializer(&reader);
        auto cs = deserializer.deserialize!(UnitTestS1[])();
        assert(cs.length == 2, cs.length.to!string);
        foreach(i; 0..cs.length)
            cs[i].assertValuesArray(i);
    }
