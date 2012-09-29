require 'spec_helper'

describe OmniAuth::Strategies::Tent do
  def app; lambda{|env| [200, {}, ["Hello."]]} end
  let(:fresh_strategy){ Class.new(OmniAuth::Strategies::Tent) }
end
