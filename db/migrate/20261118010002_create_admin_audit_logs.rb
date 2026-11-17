class CreateAdminAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_audit_logs do |t|
      t.references :admin, null: false, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.jsonb :details, null: false, default: {}
      t.string :ip
      t.datetime :created_at, null: false
    end

    add_index :admin_audit_logs, [ :subject_type, :subject_id ]
    add_index :admin_audit_logs, :created_at
    # (t.references :admin already added index_admin_audit_logs_on_admin_id)
  end
end
