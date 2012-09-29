# Omniauth::Tent (WIP)

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
| get_app_id | Yes | Should be a lambda (or anything which responds to `call`) returning either an existing app_id or `nil`. The entity URI will be passed in as a single argument. |
| on_app_created | Yes | Should respond to `call` and expect a single argument. It's called with app details when the app is first created (this happens when `get_app_id` returns `nil` or lookup fails for the given app_id) |
| app | Yes | `name`, `icon`, `url`, `description`, `scopes`, and `redirect_uris` |
| profile_info_types | Yes | Array of profile info type URIs your app wants access to |
| post_types | Yes | Array of post type URIs your app wants access to |
| notification_url | Yes | URL for receiving notifications |

## Testing

    bundle exec kicker

OR

    bundle exec rspec

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
