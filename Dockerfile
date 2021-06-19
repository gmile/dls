FROM alpine:3.14

RUN apk add --update elixir youtube-dl
RUN mix do local.hex --force, local.rebar --force
RUN elixir --eval 'Mix.install([{:plug_cowboy, "~> 2.5"}, :jason])'
ADD main.exs main.exs

CMD ["elixir", "main.exs"]
