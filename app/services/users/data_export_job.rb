module Users
  # GDPR export job: builds the account JSON, attaches it to the user
  # (`user.export`) and mails the signed link (valid 7 days).
  class DataExportJob < ApplicationJob
    queue_as :default

    def perform(user)
      export = Users::DataExport.build(user)
      user.export.attach(
        io: StringIO.new(export),
        filename: "pcmarket-export-#{user.id}.json",
        content_type: "application/json"
      )
      DataExportMailer.with(user: user).ready.deliver_later
    end
  end
end
