# A TSQL implementation of precalculated nGram values for fast fuzzy user matching with around 100k identities

# DEPENDENCIES
This script requires dbo.NGrams8K and dbo.Levenshtein

[nasty-fast-n-grams-part-1-character-level-unigrams](https://www.sqlservercentral.com/articles/nasty-fast-n-grams-part-1-character-level-unigrams)

[Attachment%201%20-%20NGrams%20Functions.sql](https://www.sqlservercentral.com/wp-content/uploads/2019/05/Attachment%201%20-%20NGrams%20Functions.sql)

[dbo.NGrams8K.sql](https://github.com/AlanBurstein/SQL-Library/blob/master/dbo.NGrams8K.sql)

[optimizing-levenshtein-algorithm-in-tsql](http://blog.softwx.net/2014/12/optimizing-levenshtein-algorithm-in-tsql.html)

#DESCRIPTION
  - [makeNGrams](https://github.com/TechlyAccurate/nGramsFindUser/blob/main/makeNGramsREADME.md) processes new identities, precalculates the nGrams and creates a table of necessary values for later user matching
  - [findUsers](https://github.com/TechlyAccurate/nGramsFindUser/blob/main/findUserREADME.md) takes the search terms and outputs possible matching userids
