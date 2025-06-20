# NAME
**findUser**

# SYNTAX
```
EXEC [dbo].[findUser] varchar(64) givenName, varchar(64) sn, int excludeActive, FLOAT nameWeight, varchar(200) var1, FLOAT var1weight, varchar(200) var2, FLOAT var2weight
```

# RETURNS
```
**TABLE** INT userId, FLOAT NGramScore, FLOAT DifferenceScore, FLOAT ReverseDifferenceScore, INT LevenshteinScore, INT HasVar1, INT HasVar2, FLOAT nameScore, FLOAT weightScore, FLOAT standardizedScore
```

# SYNOPSIS
This script searches a large user table (100k) for users which potentially match the provided variables.

The script creates a score of the first and last name similarity using DIFFERENCE, reverse DIFFERENCE, and nGram token based term frequency-inverse document frequency (TF-IDF) with a final Levenshtein pass of the top 100 results.

It also optionally matches two additional variables.

The score is combined based on the provided weights and the potential matching userIds and scoring data are returned in a table.

# DESCRIPTION
This script requires dbo.NGrams8K and dbo.Levenshtein
[nasty-fast-n-grams-part-1-character-level-unigrams](https://www.sqlservercentral.com/articles/nasty-fast-n-grams-part-1-character-level-unigrams)
[Attachment%201%20-%20NGrams%20Functions.sql](https://www.sqlservercentral.com/wp-content/uploads/2019/05/Attachment%201%20-%20NGrams%20Functions.sql)
[dbo.NGrams8K.sql](https://github.com/AlanBurstein/SQL-Library/blob/master/dbo.NGrams8K.sql)
[optimizing-levenshtein-algorithm-in-tsql](http://blog.softwx.net/2014/12/optimizing-levenshtein-algorithm-in-tsql.html)

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

# OPTIONS
- **givenName**
  - **Type**: varchar(64)
  - **Value**: the first name that will be searched
  - **REQUIRED**
    
- **sn**
  - **Type**: varchar(64)
  - **Value**: the second name that will be searched
  - **REQUIRED**

- **excludeActive**
  - **Type**: int
  - **Value**: 0 or 1. if 1 then active users will not be included in the search per line 123 (requires modifying to match your implimentation)
  - **Default**: 0

- **nameweight**
  - **Type**: FLOAT
  - **Value**: the weight to give to the final name score when combining with var1 and var2 matching weights.
  - **Default**: 1

- **var1**
  - **Type**: varchar(200)
  - **Value**: the value to match against the stored var1 (requires modifying to match your implimentation; see makeNGrams and UserValue1 / UserValue2)
  - **Default**: NULL

- **var1weight**
  - **Type**: FLOAT
  - **Value**: the weight to give to a match of var1 when combining with the final nameScore and var2 matching weights.
  - **Default**: 0

- **var2**
  - **Type**: varchar(200)
  - **Value**: the value to match against the stored var2 (requires modifying to match your implimentation; see makeNGrams and UserValue1 / UserValue2)
  - **Default**: NULL

- **var1weight**
  - **Type**: FLOAT
  - **Value**: the weight to give to a match of var2 when combining with the final nameScore and var1 matching weights.
  - **Default**: 0
 
# ENVIRONMENT
This was originally written and deployed for MS SQL 2019
