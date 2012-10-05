[![Build Status](https://secure.travis-ci.org/tent/omniauth-tent.png)](http://travis-ci.org/tent/omniauth-tent)

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

Available options (see [the Tent.io docs for details](http://tent.io/docs/app-auth))

| Option | Required | Description |
| ------ | -------- | ----------- |
| get_app | Yes | Should be a lambda (or anything which responds to `call`) returning either an existing app attributes hash or `nil`. The entity URI will be passed in as a single argument. |
| on_app_created | No | Should respond to `call`. Gets called with Hashie::Mash representation of app when created |
| app | Yes | `name`, `icon`, `url`, `description`, `scopes`, and `redirect_uris` |
| profile_info_types | Yes | Array of profile info type URIs your app wants access to |
| post_types | Yes | Array of post type URIs your app wants access to |
| notification_url | Yes | URL for receiving notifications |

## Testing

    bundle exec kicker

OR

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
