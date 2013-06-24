Sequel.migration do
  up do
    create_table :jobs do
      primary_key :id,           Integer

      foreign_key :task_id,      :tasks, :null => false

      column      :name,         String # optional, from URL
      column      :files,        String # newline separated

      column      :type,         String # X-Maru-Job-Type
      column      :description,  String # X-Maru-Job-Description
      column      :worker,       String # X-Maru-Worker-Id

      column      :submitted_at, DateTime
    end
  end

  down do
    drop_table :jobs
  end
end
