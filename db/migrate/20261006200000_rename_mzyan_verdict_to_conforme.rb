class RenameMzyanVerdictToConforme < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE deliveries SET verdict = 'conforme' WHERE verdict = 'mzyan'"
  end

  def down
    execute "UPDATE deliveries SET verdict = 'mzyan' WHERE verdict = 'conforme'"
  end
end
