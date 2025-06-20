# NAME
[**makeNGrams**](https://github.com/TechlyAccurate/nGramsFindUser/blob/main/makeNGrams.sql)

# SYNTAX
```
EXEC [ident].[makeNGrams] BIT InitialRun, varchar(max) userIds, varchar(max) attribTypes
```

# RETURNS
```
None
```

# SYNOPSIS
This script ultimately creates a table of "nGrams" of the defined attribute types along with two special identification variables which will all be used in findUser.sql to quickly perform fuzzy user matching on ~100k identities

# DESCRIPTION
This script requires dbo.NGrams8K

[nasty-fast-n-grams-part-1-character-level-unigrams](https://www.sqlservercentral.com/articles/nasty-fast-n-grams-part-1-character-level-unigrams)

[Attachment%201%20-%20NGrams%20Functions.sql](https://www.sqlservercentral.com/wp-content/uploads/2019/05/Attachment%201%20-%20NGrams%20Functions.sql)

[dbo.NGrams8K.sql](https://github.com/AlanBurstein/SQL-Library/blob/master/dbo.NGrams8K.sql)

This script can be ran with no parameters.

The script uses a transaction with Sp_getapplock, TRY/CATCH and XACT_ABORT ON.

If userIds or attributeTypes are provided they are converted from comma seperated strings into temporary tables.

If no attributeTypes are provided, then they are taken from the existing nGrams table.

If no nGrams table exists, the default values of givenName and sn are used.

If the InitialRun BIT is set to 1 the existing nGrams table is dropped.

If the nGrams table does not exist it is created.

If any userIds are provided and they already exist in the nGrams table, those rows are deleted.

Then nGrams are created for all users who exist in the ExampleAttributes but not in the nGrams table.

The total number of nGrams for each name is then calculated and added to the nGram table for findUser calculations.

Finally the two special identification variables are merged into the nGrams table and, if the table is newly created an index is created for efficient queries later.

# OPTIONS
- **InitialRun**
  - **Type**: BIT
  - **Value**: 0 or 1. If 1 the nGrams table is dropped and recreated.
  - **Default**: 0
    
- **userIds**
  - **Type**: varchar(max)
  - **Value**: comma delimited list of userIds
  - **Default**: null

- **attribTypes**
  - **Type**: varchar(max)
  - **Value**: comma delimited list of attribute types to convert into nGrams
  - **Default**: null

# ENVIRONMENT
This was originally written and deployed for MS SQL 2019
