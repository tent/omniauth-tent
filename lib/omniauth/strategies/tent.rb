require 'omniauth'

module OmniAuth
  module Strategies
    class Tent
      include OmniAuth::Strategy

      option :fields, [:app_authorization]

      def request_phase
        if request.post?
        else
          OmniAuth::Form.build(
            :title => (options[:title] || "Entity Verification")
          ) do |f|
            f.text_field 'Entity', 'entity'
          end.to_response
        end
      end

      def callback_phase
      end
    end
  end
end
