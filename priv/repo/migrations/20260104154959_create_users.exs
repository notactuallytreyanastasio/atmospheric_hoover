defmodule AtmosphericHoover.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      # Core identity
      add :did, :string, null: false
      add :handle, :string
      add :display_name, :string

      # Profile content
      add :description, :text
      add :avatar, :string
      add :banner, :string

      # Stats
      add :followers_count, :integer
      add :follows_count, :integer
      add :posts_count, :integer

      # Account metadata
      add :indexed_at, :utc_datetime_usec
      add :created_at, :utc_datetime_usec

      # Labels and verification
      add :labels, {:array, :map}, default: []

      # Associated lists (for later enrichment)
      add :associated, :map

      # Fetch status
      add :fetched_at, :utc_datetime_usec
      add :fetch_error, :string

      timestamps(type: :utc_datetime_usec)
    end

    # DID must be unique
    create unique_index(:users, [:did])

    # Handle lookups
    create index(:users, [:handle])

    # For finding users we haven't fetched yet
    create index(:users, [:fetched_at])
  end
end
