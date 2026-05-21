class ApplicationController < ActionController::Base
  # Skip CSRF token for benchmark endpoints so wrk/ab/siege can hit them directly
  skip_before_action :verify_authenticity_token
end