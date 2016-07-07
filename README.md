# Pesterbot

**TODO: Add description**

## Running
Pesterbot relies on you app id and secret token being stored in your environment. The standard approach is to create a shell file which exports the environment variables, and then source that file before starting the bot:

tokens.env:
```bash
export APP_ID="1111111111111111"
export APP_SECRET="abcdef0123456789abcdef0123456789"
export VERIFY_TOKEN="aaaaa"
export PAGE_ACCESS_TOKEN="ASDFasdfasdfASDFASdf9sdf0as9jdf98j498nf98jasidnuc94nfi7hwefQSDGASDGwqef09u948jf9q8efn723h4rSADFAf298fh9238joajdfasDFASDFj2398298fjowidjfskjdf9283ji2uj3fDFASDFQWEf2i38f9288afhASDFD"
```
to run:
```bash
source tokens.env
mix run --no-halt
```

If you are using the ngrok functionality, make sure to start ngrok using only https:
```bash
ngrok http 4000 -bind-tls=true
```


## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add pesterbot to your list of dependencies in `mix.exs`:

        def deps do
          [{:pesterbot, "~> 0.0.1"}]
        end

  2. Ensure pesterbot is started before your application:

        def application do
          [applications: [:pesterbot]]
        end
