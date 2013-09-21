require 'bcrypt'

Sequel.migration do
  up do
    create_table :users do
      column :name,     String, :primary_key => true, :null => false
      column :password, String # bcrypt. null password disables the user account.

      column :is_admin, :boolean, :null => false, :default => false

      # extra (non-essential) information

      column :full_name, String
      column :email,     String
    end

    self[:users] << {name: "admin", password: BCrypt::Password.create("admin"), is_admin: true, full_name: "Administrator"}
  end
  down do
    drop_table :users
  end
end
