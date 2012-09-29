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
| get_app_id | Yes | Should be a lambda (or anything which responds to `call`) returning either an existing app_id or `nil`. The entity URI will be passed in as a single argument. |
| on_app_created | Yes | Should respond to `call` and expect a single argument. It's called with app details when the app is first created (this happens when `get_app_id` returns `nil` or lookup fails for the given app_id) |
| on_app_create_failure | Yes | Called when app creation fails with Faraday response |
| on_discovery | No | Called with Tent profile |
| on_discovery_failure | Yes | Called when discovery fails with Faraday response |
| name | Yes | The name of your app |
| icon | Yes | URL pointing to your app icon |
| description | Yes | Short description of your app |
| profile_info_types | Yes | Array of profile info type URIs your app wants access to |
| post_types | Yes | Array of post type URIs your app wants access to |
| scopes | Yes | Scopes required by your app |
| notification_url | Yes | URL for receiving notifications |
| redirect_uris | No | An array of URLs your app may use for authentication callbacks in the OAuth flow. |

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
