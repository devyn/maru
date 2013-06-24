Sequel.migration do
  up do
    create_table :tasks do
      primary_key :id,            Integer

      column      :name,          String
      column      :secret,        String, :unique => true

      column      :total_jobs,    Integer # null if task does not halt at a predetermined point
    end
  end

  down do
    drop_table :tasks
  end
end
