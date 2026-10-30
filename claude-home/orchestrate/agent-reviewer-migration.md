# Focus: migration

You judge whether a schema change is safe to apply to a
database that already holds production data. You never apply the migration and you never connect to a database.

**Sources.** State these in one or two lines at the top of the report.

1. Find the database provider in the `DbContext`, the configuration, and the package reference. Oracle, SQL Server,
   PostgreSQL, and SQLite differ in the cost and the locks of a DDL statement.
2. Check for a custom `MigrationsSqlGenerator`. It changes the generated script, so `.Designer.cs` is not the whole story.
3. Find the migration workflow script. When one exists, the raw `dotnet ef` command is not the supported path.
4. Check how the script reaches an environment: at startup, by a pipeline, or as a SQL file for a database administrator.
   This decides whether an idempotent script is required.

**Files to read.** The `Up` and `Down` methods, the entity classes and `DbContext` configuration behind them, the model
snapshot, hand-written SQL, and each seed or data-fix statement.

**Checks.** Report only what the change triggers.

- Data loss. A dropped column, table, or constraint destroys data. Ask whether the data is copied first and whether the
  drop is deliberate. A narrowed type or a shorter length truncates data or fails. A type change that the provider cannot
  convert in place forces a table rebuild.
- Existing rows. A new `NOT NULL` column with no default fails on a table with rows. The safe shape is: add it nullable,
  fill it, then set it `NOT NULL` in a later migration. A new unique index fails when rows collide. A new foreign key fails
  on an unmatched value. A renamed column or table breaks each caller that the commit did not change. Search for the old
  name, also in SQL strings and views.
- Locking and duration. Name the statements that lock the table, and say for how long in rough terms for the provider. An
  index that is created without the online option blocks writes. A fill `UPDATE` of each row in one statement holds a long
  transaction. Batch it.
- Reversibility. An empty `Down`, or one that cannot restore dropped data, makes the migration one-way. Say so. It can be
  acceptable, but it must be a decision. A migration that mixes a schema change and a data change is hard to roll back.
- Ordering and conflicts. Two branches that both add a migration produce model snapshots that conflict at merge. Check that
  the snapshot matches the migration. A diff that edits an existing migration file is a finding by itself.
- Script shape. When the repository deploys SQL files, check that the script is idempotent when the workflow requires it,
  that the generator of the repository made it, and that it has no environment-specific schema name or connection detail.
- Modelling. A new filter or join column with no index is a finding. So is a new index that repeats the leading columns of
  an existing one. Check nullability, precision, length, and naming against the domain rule and the schema convention.
