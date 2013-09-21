Sequel.migration do
  up do
    alter_table :tasks do
      # visibility_level, enum.
      #   0: public. visible to everyone, including non-logged in users.
      #   1: members-only. visible to anyone who is logged in.
      #   2: private. only visible to those explicitly allowed to access the task.
      add_column :visibility_level, :integer, :null => false, :default => 2

      # If true, the results of the task are available to anyone able to see the task,
      # regardless of relationship.
      add_column :results_are_public, :boolean, :null => false, :default => false
    end
  end
  down do
    alter_table :tasks do
      drop_column :visibility_level
      drop_column :results_are_public
    end
  end
end
