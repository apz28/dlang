1. Allow to handling queries to various database vendors with no code change except proprietary SQL construct
2. Pure D implementation, no DLL hell
3. Handling database encryption communication

Samples:
Create connection
    // FbConnection [DbConnection\SkConnection\FbConnection]
    auto connection = DbDatabaseList.createConnection("firebird:server=myServerAddress;database=myDataBase;" ~
        "user=myUsername;password=myPassword;role=myRole;pooling=true;connectionTimeout=100seconds;encrypt=enabled;" ~
        "fetchRecordCount=50;integratedSecurity=legacy;cachePage=2000;cryptKey=QUIx;");
	
    // MyConnection [DbConnection\SkConnection\MyConnection]
    auto connection = DbDatabaseList.createConnection("mysql:server=myServerAddress;database=myDataBase;" ~
        "user=myUsername;password=myPassword;role=myRole;pooling=true;connectionTimeout=100seconds;encrypt=enabled;" ~
        "fetchRecordCount=50;integratedSecurity=legacy;");

    // PgConnection [DbConnection\SkConnection\PgConnection]
    auto connection = DbDatabaseList.createConnection("postgresql:server=myServerAddress;database=myDataBase;" ~
        "user=myUsername;password=myPassword;role=myRole;pooling=true;connectionTimeout=100seconds;encrypt=enabled;" ~
        "fetchRecordCount=50;integratedSecurity=legacy;");

Create command and execute
    // FbCommand [DbCommand\SkCommand\FbCommand]
    // MyCommand [DbCommand\SkCommand\MyCommand]
    // PgCommand [DbCommand\SkCommand\PgCommand]
    auto command = connection.createCommandText("...");
    auto rowAffected = command.executeNonQuery(); // Execute a command without returning a result set
    command.executeReader(); // Execute a command and returning a result set
    auto firstColumnValue = command.executeScalar(); // Execute a command and returning the first row & column from result set
        
Prefer to simple execution from a connection
    auto TEXT_FIELD = connection.executeScalar("select TEXT_FIELD from TEST_SELECT where INT_FIELD = 1");
    if (!TEXT_FIELD.isNull)
	assert(TEXT_FIELD.get!string() == "TEXT...");
