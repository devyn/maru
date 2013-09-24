Sequel.migration do
  up do
    # Stores authentication information for users' clients.
    create_table :clients do
      primary_key :id
      foreign_key :user_name, :users, :null => false, :type => String

      column :remote_host, String,  :null => false
      column :remote_port, Integer, :null => false

      column :name, String, :null => false
      column :key,  String, :null => false

      unique [:remote_host, :remote_port, :name]

      # Client permissions.

      column :is_producer, :boolean, :null => false, :default => false
    end

    alter_table :jobs do
      add_foreign_key :produced_by, :clients
    end
  end
  down do
    alter_table :jobs do
      drop_column :produced_by
    end

    drop_table :clients
  end
end
