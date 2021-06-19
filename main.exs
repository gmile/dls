Mix.install([{:plug_cowboy, "~> 2.5"}, :jason])

require Logger

defmodule Router do
  use Plug.Router

  @tg_bot_token System.fetch_env!("TG_BOT_TOKEN")
  @download_path System.fetch_env!("DOWNLOAD_PATH")
  @download_name_template System.fetch_env!("DOWNLOAD_NAME_TEMPLATE")

  @output "#{@download_path}/#{@download_name_template}"

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    json_decoder: Jason

  plug(Plug.Logger)
  plug(:match)
  plug(:dispatch)

  post "/:tg_bot_token" when tg_bot_token == @tg_bot_token do
    send_resp(conn, 200, "OK")
  end

  # Save
  post "/save-from-tg" do
    Logger.info(inspect(conn.req_headers))
    %{"message" => %{"text"=> url}} = conn.body_params

    %{pid: pid} = Task.async(fn ->
      Logger.info("Calling: youtube-dl #{url} --output #{@output}")
      System.cmd("youtube-dl", [url, "--output", @output], into: IO.stream())
      Logger.info("Saved: #{url}")
    end)

    send_resp(conn, 202, "OK - queued task #{inspect(pid)}")
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end

plug_cowboy = {Plug.Cowboy, plug: Router, scheme: :http, port: 4000}
Logger.info("starting #{inspect(plug_cowboy)}")
{:ok, _} = Supervisor.start_link([plug_cowboy], strategy: :one_for_one)

Process.sleep(:infinity)
