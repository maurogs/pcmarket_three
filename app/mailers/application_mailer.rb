class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  # Order e-mails format amounts with the shared money() helper.
  helper ListingsHelper
end
