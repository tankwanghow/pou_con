# PouCon

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix

PORT=4000 MIX_ENV=prod DATABASE_PATH=./pou_con_dev.db SECRET_KEY_BASE=opGt7yCWMpZAxFrFpm1YsqP/YOha/zo2YiuJvKJMZj+mX8zCFq8mXh9+is9Y1p0g PHX_HOST=localhost mix phx.server