Sequel.migration do
  up do
    create_table :task_user_relationships do
      foreign_key :task_id,   :tasks, :null => false
      foreign_key :user_name, :users, :null => false, :type => String

      primary_key [:task_id, :user_name]

      # relationship_type, enum.
      #   0: status-only. if the task is private, this allows the user to see the status of the task
      #   1: status and results. allows the user to download the task's results. has no effect on tasks
      #        with 'results_are_public' = true
      #   2: contributor. allows the user to use their producer to contribute to the task.
      #   3: owner. allows complete control over the task, including deletion.
      column :relationship_type, Integer, :null => false, :default => 0
    end
  end
  down do
    drop_table :task_user_relationships
  end
end
