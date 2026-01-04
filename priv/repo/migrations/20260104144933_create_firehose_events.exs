defmodule AtmosphericHoover.Repo.Migrations.CreateFirehoseEvents do
  use Ecto.Migration

  def change do
    create table(:firehose_events) do
      # Event metadata
      add :did, :string, null: false
      add :time_us, :bigint, null: false
      add :kind, :string, null: false

      # Commit fields
      add :rev, :string
      add :operation, :string
      add :collection, :string
      add :rkey, :string
      add :cid, :string

      # Record data stored as JSONB for flexibility
      add :record, :map

      # Identity/Account fields
      add :handle, :string
      add :active, :boolean
      add :status, :string
      add :seq, :bigint

      timestamps(type: :utc_datetime_usec)
    end

    # Index for time-based queries
    create index(:firehose_events, [:time_us])

    # Index for filtering by DID
    create index(:firehose_events, [:did])

    # Index for filtering by collection type
    create index(:firehose_events, [:collection])

    # Index for filtering by operation
    create index(:firehose_events, [:operation])

    # Composite index for common queries
    create index(:firehose_events, [:collection, :operation, :time_us])

    # Unique constraint to prevent duplicates (did + collection + rkey)
    create unique_index(:firehose_events, [:did, :collection, :rkey],
             where: "collection IS NOT NULL AND rkey IS NOT NULL",
             name: :firehose_events_unique_record
           )
  end
end
