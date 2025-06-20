USE [ExampleDatabase]
GO
/****** Object:  StoredProcedure [ident].[makeNGrams]   ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [ident].[makeNGrams] 
	@InitialRun BIT = 0, --Send 1 to rebuild. Warning: This could take a very long time depending on the number of users and number of roles
	@userIds VARCHAR(MAX) = null,
	@attribTypes VARCHAR(MAX) = null
AS
BEGIN
SET XACT_ABORT ON;
BEGIN TRY
	DECLARE @timeoutToWaitForLock numeric = 60000*5;
	DECLARE @gramSize int = 2;
	DECLARE @TransactionName VARCHAR(128) ='makeNGrams';

	IF @InitialRun = 1
	BEGIN
		RAISERROR (N'This is an Initial Run.', 0, 1)
		WITH NOWAIT;
		RAISERROR (N'Existing nGram table values will be lost!', 0, 1)
		WITH NOWAIT;
	END

	CREATE TABLE #userIds  (
			userIds INT NOT NULL INDEX IX1(userIds)
			)
	CREATE TABLE #attribTypes  (
			attribType VARCHAR(128) NOT NULL INDEX IX1(attribType)
			)
		 
	--Converting comma seperated string into IDs that can be put in a #temp table
	IF @userIds IS NOT NULL
	BEGIN
		RAISERROR (N'userIds are %s', 0, 1, @userIds)
		WITH NOWAIT;
		Insert into #userIds (userIds)
		SELECT Ids = y.i.value('(./text())[1]', 'nvarchar(1000)')             
		FROM 
		( 
		SELECT 
			n = CONVERT(XML, '<i>' 
				+ REPLACE(REPLACE(@userIds,' ',''), ',' , '</i><i>') 
				+ '</i>')
		) AS a 
		CROSS APPLY n.nodes('i') AS y(i)
	END
	
	--Converting comma seperated string into attribTypes that can be put in a #temp table
	IF @attribTypes IS NOT NULL
	BEGIN
		INSERT INTO #attribTypes (attribType)
		SELECT attribTypes = y.i.value('(./text())[1]', 'nvarchar(1000)')             
		FROM 
		( 
		SELECT 
			n = CONVERT(XML, '<i>' 
				+ REPLACE(REPLACE(@attribTypes,' ',''), ',' , '</i><i>') 
				+ '</i>')
		) AS a 
		CROSS APPLY n.nodes('i') AS y(i)
	END
	ELSE IF (@attribTypes IS NULL 
		AND OBJECT_ID(N'ident.nGrams', N'U') IS NOT NULL
		AND	(SELECT COUNT(DISTINCT attribType) FROM [ident].[nGrams]) > 0)
	BEGIN
		RAISERROR (N'attribTypes is NULL...', 0, 1)
		WITH NOWAIT;
		RAISERROR (N'Setting attribTypes from the existing nGrams table.', 0, 1)
		WITH NOWAIT;

		INSERT INTO #attribTypes (attribType)
		SELECT DISTINCT attribType
		FROM [ident].[nGrams];
	END
	ELSE IF (@attribTypes IS NULL)
	BEGIN
		RAISERROR (N'attribTypes is NULL...', 0, 1)
		WITH NOWAIT;
		RAISERROR (N'No existing nGram attribTypes...', 0, 1)
		WITH NOWAIT;
		RAISERROR (N'Setting attribTypes to default values.', 0, 1)
		WITH NOWAIT;

		INSERT INTO #attribTypes (attribType)
		VALUES ('givenName'),('sn');	
	END

	DECLARE @attribTypesList VARCHAR(MAX);
	SET @attribTypesList = (
						SELECT
						STRING_AGG(val,',') AS StringAggList
						FROM (
						select distinct attribType as val
						FROM #attribTypes
						) x
						);
	RAISERROR (N'attribTypes = %s', 0, 1, @attribTypesList)
	WITH NOWAIT;

	DECLARE @returnLock INT
	
	RAISERROR (N'Beginning transaction', 0, 1)
	WITH NOWAIT;

	BEGIN TRANSACTION @TransactionName

	DECLARE @message VARCHAR(2047);
	SET @message = CONCAT(
					N'attempting to get applock with timeout of ',
					FORMAT(@timeoutToWaitForLock,'0'));
	RAISERROR (@message, 0, 1)
	WITH NOWAIT;

	EXEC @returnLock = Sp_getapplock
         @Resource = 'ident.makeNGrams',
         @LockMode = 'Exclusive',
         @LockOwner = 'Transaction',
         @LockTimeout = @timeoutToWaitForLock
 
    IF @returnLock < 0
    BEGIN;
    THROW
		50001,
        'Unable to aquire exclusive lock on the stored procedure ident.makeNGrams.',
        1;
	END;
	ELSE
	BEGIN
		RAISERROR (N'applock obtained with code: %d', 0, 1, @returnLock)
		WITH NOWAIT;
	END

	IF @InitialRun = 1
	BEGIN
		DROP TABLE IF EXISTS ident.nGrams;
		RAISERROR (N'Dropped nGrams table...', 0, 1)
		WITH NOWAIT;
	END

	IF OBJECT_ID(N'ident.nGrams', N'U') IS NULL 
    BEGIN
        SET @InitialRun = 1; --Initial Run.
    END

	IF @InitialRun = 1
	BEGIN
		CREATE TABLE ident.nGrams(
		userId int NOT NULL,
		val nvarchar(130),
		totalNGrams int,
		position int, 
		token nvarchar(100),
		attribType varchar(64) NOT NULL,
		UserValue1 varchar(200),
		UserValue2 varchar(200)
		);
		RAISERROR (N'Created new nGrams table...', 0, 1)
		WITH NOWAIT;
	END

	IF ( @InitialRun = 0
		 AND @userIds IS NOT NULL )
	BEGIN
		DELETE FROM ident.nGrams
		WHERE userId IN (SELECT userIds FROM #userIds);
		RAISERROR (N'Deleted nGrams rows for the following users: %s', 0, 1, @userIds)
		WITH NOWAIT;
	END

	DECLARE @sql NVARCHAR(2000);
	DECLARE @params NVARCHAR(2);
	Declare @attribType VARCHAR(128);

	WHILE(1=1)
	BEGIN
		SET @attribType = NULL;
		SELECT TOP(1) @attribType = attribType
		FROM #attribTypes

		IF @attribType IS NULL
			BREAK
		
		RAISERROR (N'Building nGrams entries for attrib %s', 0, 1, @attribType)
		WITH NOWAIT;
		
		Set @sql = 
			N'SELECT userId, '+@attribType+' as val, gramTbl.position, gramTbl.token, '''+@attribType+''' as attribType 
			FROM [dbo].[ExampleAttributes] AS a
			CROSS APPLY dbo.NGrams8K(UPPER('+@attribType+'), '+CAST(@gramSize as varchar(4))+') as gramTbl '
			
		SET @sql = @sql + CASE 
		WHEN @userIds IS NULL THEN 'WHERE NOT EXISTS (SELECT 1 FROM ident.nGrams AS b WHERE a.userId = b.userId AND b.attribType = '''+@attribType+''')'
		WHEN @userIds IS NOT NULL THEN 'WHERE EXISTS (SELECT 1 FROM #userIds AS b WHERE a.userId = b.userIds)' END

		INSERT INTO ident.nGrams (userId, val, position, token, attribType)
		EXEC sp_Executesql @sql,@params;

		DELETE TOP(1) FROM #attribTypes
	END

	UPDATE ident.nGrams
	SET totalNGrams = b.totalNGrams
	FROM ident.nGrams AS a
	INNER JOIN (
		SELECT userId, attribType, val, COUNT(*) AS totalNGrams
		FROM ident.nGrams
		WITH (NOLOCK)
		GROUP BY userId, attribType, val
	) AS b
	ON a.userId = b.userId AND a.attribType = b.attribType AND a.val = b.val AND (a.totalNGrams IS NULL OR a.totalNGrams = '')
	

	MERGE ident.nGrams AS tar
	USING 
	(
		SELECT [userId]
			  ,[UserValue1]
		FROM [ExampleDatabase].[dbo].[ExampleAttributes]
		WHERE UserValue1 IS NOT NULL
		GROUP BY userId, UserValue1
	)AS sor
	ON sor.userId = tar.userid AND (tar.UserValue1 IS NULL OR tar.UserValue1 = '')
	WHEN MATCHED 
	THEN UPDATE SET
	tar.UserValue1 = sor.UserValue1;


	MERGE ident.nGrams AS tar
	USING 
	(
		SELECT [userId]
			  ,[UserValue2]
		FROM [ExampleDatabase].[dbo].[ExampleAttributes]
		WHERE UserValue2 IS NOT NULL
		GROUP BY userId, UserValue2
	)AS sor
	ON sor.userId = tar.userid AND (tar.UserValue2 IS NULL OR tar.UserValue2 = '')
	WHEN MATCHED 
	THEN UPDATE SET
	tar.UserValue2 = sor.UserValue2;

	IF @InitialRun = 1
	BEGIN
		CREATE NONCLUSTERED INDEX IX_attribType_token_position
		ON ident.nGrams (attribType, token, position)
		INCLUDE (userId, val, totalNGrams);
		RAISERROR (N'Created nGrams index', 0, 1)
		WITH NOWAIT;
	END

	COMMIT TRANSACTION @TransactionName
	RAISERROR (N'COMMITTED TRANSACTION', 0, 1)
	WITH NOWAIT;

END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION @TransactionName;
	RAISERROR (N'ROLLED BACK TRANSACTION!', 0, 1)
	WITH NOWAIT;
	DECLARE @ErrStr NVARCHAR(MAX) = ERROR_MESSAGE() 
	DECLARE @ErrNum INT = ERROR_NUMBER() 
	DECLARE @procName NVARCHAR(128) = OBJECT_NAME(@@PROCID) 

	RAISERROR (N'Error in %s: %s and error code: %d', -- Message text.
				18, -- Severity,
				1, -- State,
				@procName, -- First argument.
				@ErrStr,
				@ErrNum); 
END CATCH
END
