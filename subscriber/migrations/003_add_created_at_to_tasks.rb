Sequel.migration do
  up do
    alter_table :tasks do
      add_column :created_at, DateTime, :default => Sequel::CURRENT_TIMESTAMP
    end
  end
  down do
    alter_table :tasks do
      drop_column :created_at
    end
  end
end
