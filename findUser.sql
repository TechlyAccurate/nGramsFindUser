USE [ExampleDatabase]
GO
/****** Object:  StoredProcedure [dbo].[findUser]  ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[findUser]
    @givenName varchar(64),
    @sn varchar(64),
	@excludeActive int = 0,
	@nameweight FLOAT = 1,
	@var1 varchar(200) = null,
	@var1weight FLOAT = 0,
	@var2 varchar(200) = null,
	@var2weight FLOAT = 0
AS
BEGIN
    SET NOCOUNT ON;
	
	/**
	This script requires dbo.NGrams8K and dbo.Levenshtein
	https://www.sqlservercentral.com/articles/nasty-fast-n-grams-part-1-character-level-unigrams
	https://www.sqlservercentral.com/wp-content/uploads/2019/05/Attachment%201%20-%20NGrams%20Functions.sql
	https://github.com/AlanBurstein/SQL-Library/blob/master/dbo.NGrams8K.sql
	http://blog.softwx.net/2014/12/optimizing-levenshtein-algorithm-in-tsql.html

	This script creates a score of the first and last name similarity using 
	DIFFERENCE, reverse DIFFERENCE, and nGram token based term frequency-inverse document frequency (TF-IDF)
	with a final Levenshtein pass of the top 100 results.

	This is done by taking the combined first and last name normalized nGram scores, difference scores and reverse difference scores
	to generate a nameScore.

	A preliminary weightedScore is then generated using the provided weights for nameScore, userValue1 and userValue2.

	The preliminary weightedScore is used to generate a list of the top 100 results.

	The Levenshtein score is calculated for the top 100 results first and last name and that value is used to adjust the nameScore.

	The final weightedScore is then recalculated using the adjusted nameScore.

	Lastly a standard deviation is ran on the final weightedScores and all scores below the average are dropped.

	Then the deviation above the average weightedScore is returned as a percentage.

	---------------------------

	In order to properly calculate scores all values are normalized to a value between 0 and 1 (i.e. a percentage)

	The outlined method is used because the tf-idf token search is an extremely fast search to perform in a relational database 
	leveraging precalculated tokens.

	The difference and reverse difference are similarly fast and are used to better match names specifically. Combining these with 
	the if-idf value helps match extremely short names much better as well as increases matching against typos by accurately matching 
	the beginning and ending of names.

	Levenshtein is a very slow algorithm since it has to be ran on each value individually at the time of the search but it greatly increases
	the accuracy of the name search, especially in regards to identifying typos compared to similar but different names. Since Levenshtein 
	is so much slower though, this is only calculated for the top 100 results using the previous methods.

	Finally standard deviation is used to map the scores onto a curve with the average exactly in the middle and a perfect match as a maximum deviation.

	The results with average or below standard deviation are dropped and the remaining results are returned using the deviation above average as the
	score percentage.

	**/

	BEGIN TRY
		DECLARE @gramSize int = 2;
		DECLARE @posVariance int = 3;

		IF(		LEN(@givenName) < @gramSize
			OR	LEN(@sn) < @gramSize)
		BEGIN
			RAISERROR (N'The search terms %s and %s must be at least %d characters long.', -- Message text.
				11, -- Severity,
				1,
				@givenName,
				@sn,
				@gramSize);
		END

		CREATE TABLE #inVal (
			position int NOT NULL, 
			token varchar(4) NOT NULL,
			attribType varchar(64) NOT NULL,
			val varchar(64) NOT NULL
		);

		INSERT INTO #inVal
			SELECT position, token, attribType = 'givenName', val = @givenName
			FROM dbo.NGrams8K(UPPER(@givenName), @gramSize)
			UNION ALL
			SELECT position, token, attribType = 'sn', val = @sn
			FROM dbo.NGrams8K(UPPER(@sn), @gramSize)

		CREATE TABLE #resultTbl 
		(
			userId int,
			val varchar(100),
			attribType varchar(100),
			Score float,
			Diff float,
			RevDiff float,
			Matches float,
			UserValue1 varchar(200),
			UserValue2 varchar(200),
			possibleNGrams float,
			inValNGrams float,
			entityStatusId int
		);

		INSERT INTO #resultTbl (userId, val, attribType, possibleNGrams, Matches, UserValue1, UserValue2)
		SELECT a.userId, a.val, a.attribType, possibleNGrams = a.totalNGrams,  COUNT(*) AS Matches, a.UserValue1, a.UserValue2
		FROM #inVal AS b
		INNER JOIN
		(
			SELECT a.userId, a.val, a.totalNGrams, a.position, a.token, a.attribType, a.UserValue1, a.UserValue2
			FROM ident.nGrams AS a
			WITH (NOLOCK)
			WHERE EXISTS (SELECT 1 FROM [dbo].[ExampleAttributes] AS s WHERE (@excludeActive = 1 AND a.userId = s.userId AND s.provisionEntityId = 1 AND s.entityStatusId >= 4) OR (@excludeActive = 0 AND a.userId = s.userId))
		) AS a
		ON (a.attribType = b.attribType AND a.token = b.token AND a.position >= b.position-@posVariance AND a.position <= b.position+@posVariance)
		GROUP BY a.userId, a.attribType, a.val, a.totalNGrams, a.UserValue1, a.UserValue2

		CREATE NONCLUSTERED INDEX IX_attribType
		ON #resultTbl ([attribType])
		INCLUDE ([val],[Matches],[possibleNGrams])

		UPDATE a
		SET
		a.inValNGrams = c.inValNGrams,
		a.Score = (Matches / (SELECT MAX(GreatestVal) FROM (VALUES(c.inValNGrams), (a.possibleNGrams)) AS T(GreatestVal))),
		a.Diff = DIFFERENCE(c.val, a.val),
		a.RevDiff = DIFFERENCE(REVERSE(c.val), REVERSE(a.val))
		FROM #resultTbl a
		INNER JOIN (
			SELECT a.attribType, a.val, COUNT(*) AS inValNGrams
			FROM #inVal AS a
			GROUP BY a.attribType, a.val
		) AS c
		ON a.attribType = c.attribType

		CREATE TABLE #finalTbl 
		(
			userId INT,
			NGramScore FLOAT,
			DiffScore FLOAT,
			RevDiffScore FLOAT,
			LevScore INT,
			hasvar1 INT,
			hasvar2 INT,
			nameScore FLOAT,
			weightedScore FLOAT
			--,Diag FLOAT
		);

		INSERT INTO #finalTbl (userId)
		SELECT DISTINCT userId
		FROM #resultTbl

		DECLARE @numOfAttribs INT = (SELECT COUNT(DISTINCT attribType) FROM #inVal);

		UPDATE f
		SET 
		NGramScore = r.summedScore / @numOfAttribs,
		DiffScore = r.Diff / (@numOfAttribs * 4),
		RevDiffScore = r.RevDiff / (@numOfAttribs * 4),
		hasvar1 = (CASE 
					WHEN @var1 IS NOT NULL AND @var1 != '' AND @var1 = r.UserValue1 THEN 1 
					WHEN @var1 IS NOT NULL AND @var1 != '' AND @var1 != r.UserValue1 THEN 0
					ELSE NULL END),
		hasvar2 = (CASE
					WHEN @var2 IS NOT NULL AND @var2 != '' AND @var2 = r.UserValue2 THEN 1 
					WHEN @var2 IS NOT NULL AND @var2 != '' AND @var2 != r.UserValue2 THEN 0
					ELSE NULL END),
		nameScore = ((r.summedScore / @numOfAttribs) + (CAST((r.Diff / (@numOfAttribs * 4)) + (r.RevDiff / (@numOfAttribs * 4)) AS FLOAT) / 2)) / 2,
		weightedScore = (((((r.summedScore / @numOfAttribs) + (CAST((r.Diff / (@numOfAttribs * 4)) + (r.RevDiff / (@numOfAttribs * 4)) AS FLOAT) / 2)) / 2)
						*(@nameweight / (@nameweight 
										+ (CASE WHEN @var1 IS NOT NULL AND @var1 != '' THEN @var1weight ELSE 0 END) 
										+ (CASE WHEN @var2 IS NOT NULL AND @var2 != '' THEN @var2weight ELSE 0 END)))) 
						+ (CASE WHEN @var1 IS NOT NULL AND @var1 != '' AND @var1 = r.UserValue1 THEN (@var1weight / (@nameweight + @var1weight + (CASE WHEN @var2 IS NOT NULL AND @var2 != '' THEN @var2weight ELSE 0 END))) ELSE 0 END) 
						+ (CASE WHEN @var2 IS NOT NULL AND @var2 != '' AND @var2 = r.UserValue2 THEN (@var2weight / (@nameweight + (CASE WHEN @var1 IS NOT NULL AND @var1 != '' THEN @var1weight ELSE 0 END) + @var2weight)) ELSE 0 END))
		FROM #finalTbl AS f
		INNER JOIN (
			SELECT userId, UserValue1, UserValue2, SUM(Score) AS summedScore, CAST(SUM(Diff) as float) as Diff, CAST(SUM(RevDiff) as float) RevDiff
			FROM #resultTbl
			GROUP BY userId, UserValue1, UserValue2
		) AS r ON f.userId = r.userId
	
		DECLARE @temp TABLE(
			userId INT,
			NGramScore FLOAT,
			DiffScore FLOAT,
			RevDiffScore FLOAT,
			LevScore INT,
			hasvar1 INT,
			hasvar2 INT,
			nameScore FLOAT,
			weightedScore FLOAT
			--,Diag FLOAT
			)

		INSERT INTO @temp (userId, NGramScore, DIffSCore, RevDiffScore, hasvar1, hasvar2, nameScore, weightedScore)
			SELECT TOP (100) userId, NGramScore, DIffSCore, RevDiffScore, hasvar1, hasvar2, nameScore, weightedScore
			FROM #finalTbl
			ORDER BY weightedScore Desc

		UPDATE a
		SET
		LevScore = ([dbo].[Levenshtein](c.givenName,b.givenName,NULL) + [dbo].[Levenshtein](d.sn,b.sn,NULL))
		FROM @temp a
		CROSS APPLY
		(
		SELECT userId, givenName, sn
		FROM dbo.ExampleAttributes
		) as b
		CROSS APPLY
		(SELECT attribType, val as givenName
		FROM #inVal
		WHERE attribType = 'givenName'
		) as c
		CROSS APPLY
		(SELECT attribType, val as sn
		FROM #inVal
		WHERE attribType = 'sn'
		) as d
		WHERE a.userId = b.userId

		DECLARE @maxLevScore FLOAT = (SELECT MAX(LevScore) FROM @temp);

		UPDATE a
		SET
		--Diag = Score,
		weightedScore = 
		(CAST((a.nameScore / CAST((CAST(a.LevScore+1 AS FLOAT) / CAST(@maxLevScore+1 AS FLOAT)) AS FLOAT)) 
		/ CAST(@maxLevScore+1 AS FLOAT) AS FLOAT)
		*(@nameweight / (@nameweight 
										+ (CASE WHEN @var1 IS NOT NULL AND @var1 != '' THEN @var1weight ELSE 0 END) 
										+ (CASE WHEN @var2 IS NOT NULL AND @var2 != '' THEN @var2weight ELSE 0 END)))) 
						+ (CASE WHEN @var1 IS NOT NULL AND @var1 != '' AND a.hasvar1 != 0 THEN (@var1weight / (@nameweight + @var1weight + (CASE WHEN @var2 IS NOT NULL AND @var2 != '' THEN @var2weight ELSE 0 END))) ELSE 0 END) 
						+ (CASE WHEN @var2 IS NOT NULL AND @var2 != '' AND a.hasvar2 != 0 THEN (@var2weight / (@nameweight + (CASE WHEN @var1 IS NOT NULL AND @var1 != '' THEN @var1weight ELSE 0 END) + @var2weight)) ELSE 0 END)
		--,Diag = (@maxLevScore)
		FROM @temp a
		
		DECLARE @stDv FLOAT = (SELECT STDEV(x.[weightedScore]) FROM (SELECT weightedScore FROM @temp UNION SELECT weightedScore = 1) as x);
		DECLARE @avrg FLOAT = (SELECT AVG(y.[weightedScore]) FROM (SELECT weightedScore FROM @temp UNION SELECT weightedScore = 1) as y);
		DECLARE @maxDv FLOAT = ((1 - @avrg) / @stDv);

		SELECT *, standardizedScore = (((weightedScore - @avrg) / @stDv) / @maxDv) / weightedScore
		FROM @temp
		WHERE 
		weightedScore > @avrg
		ORDER BY (((weightedScore - @avrg) / @stDv) / @maxDv) / weightedScore DESC
		

		-- Clean up temporary tables
		DROP TABLE #inVal;
		DROP TABLE #resultTbl;
		DROP TABLE #finalTbl;
END TRY
BEGIN CATCH
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
END;
