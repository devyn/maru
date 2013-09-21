Sequel.migration do
  up do
    alter_table :jobs do
      add_column :produced_at, DateTime
    end
  end
  down do
    alter_table :jobs do
      drop_column :produced_at
    end
  end
end
