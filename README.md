[![Build Status](https://travis-ci.org/tent/omniauth-tent.png?branch=0.3)](https://travis-ci.org/tent/omniauth-tent)

# Omniauth::Tent

Omniauth strategy for Tent.

## Installation

Add this line to your application's Gemfile:

    gem 'omniauth-tent'


## Usage

```ruby
use OmniAuth::Builder do
  provider :tent, options
end
```

Available options (see the Tent.io docs for details)

| Option | Required | Description |
| ------ | -------- | ----------- |
| get_app | Yes | Should be a lambda (or anything which responds to `call`) returning either an existing app attributes hash or `nil`. The entity URI will be passed in as a single argument. |
| on_app_created | No | Should respond to `call`. Gets called with Hashie::Mash representation of app when created |
| app | Yes | `name`, `description`, `url`, `redirect_uri`, `read_post_types`, `write_post_types`, `notification_post_types`, `notification_url`, `scopes` |

## Testing

    bundle exec rspec

## Contributing

Here are some tasks that need to be done:

- Handle being passed an 'error' param in the callback_phase
- Find bugs and fix them

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
