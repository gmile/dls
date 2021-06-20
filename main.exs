Mix.install([{:plug_cowboy, "~> 2.5"}, :jason])

require Logger

defmodule Router do
  use Plug.Router

  @tmp_dir System.tmp_dir()
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

  # TODO: this is not really needed. Instead of this, update "save-from-tg" URL
  # below to one of the following:
  #
  #   post "/:tg_bot_token/save"
  #   post "/:tg_bot_token/save-from-tg"
  #   post "/:random-string-configured-during-webhook-setup/save"
  #   post "/:random-string-configured-during-webhook-setup/save-from-tg"
  #
  #     Memo: to configure WebHook, run:
  #
  #       curl "https://api.telegram.org/botxxxxxxxxxx:yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy/setWebhook?url=https://server.com/optionally/some-path"
  #
  post "/:tg_bot_token" when tg_bot_token == @tg_bot_token do
    send_resp(conn, 200, "OK")
  end

  # TODO: Add support for:
  #
  #   https://github.com/mikf/gallery-dl
  #
  # Save
  post "/save-from-tg" do
    %{pid: pid} = Task.async(fn -> process_message(conn.body_params) end)

    send_resp(conn, 202, "OK - queued task #{inspect(pid)}")
  end

  def say(chat_id, message_id, text) do
    query = URI.encode_query(%{
      text: text,
      chat_id: chat_id,
      parse_mode: "Html",
      reply_to_message_id: message_id,
      disable_notification: true,
      disable_web_page_preview: true
    })

    :httpc.request("https://api.telegram.org/bot#{@tg_bot_token}/sendMessage?#{query}")
  end

  def process_message(%{"message" => %{"message_id" => message_id, "text"=> "all", "chat" => %{"id" => chat_id}}}) do
    message =
      """
      <pre>
      #{Path.wildcard(@download_path <> "/*") |> Enum.join("\n")}
      </pre>
      """

    say(chat_id, message_id, message)
  end

  def process_message(%{"message" => %{"message_id" => message_id, "text"=> text, "chat" => %{"id" => chat_id}}}) do
    Logger.info("Calling: youtube-dl #{text} --output #{@output}")

    {log, log_path} = start_log()

    {lines, status} =
      Enum.reduce_while([:youtube_dl, :gallery_dl], {[], 0}, fn tool, {acc_lines, _status} ->
        case apply(Router, tool, [text, log]) do
          {lines, 0} -> {:halt, {lines, 0}}
          {lines, status} -> {:cont, {acc_lines ++ lines, status}}
        end
      end)

    say(chat_id, message_id, log(status, lines))

    File.rm!(log_path)

    Logger.info("Saved: #{text}")
  end

  def youtube_dl(text, log), do: System.cmd("youtube-dl", [text, "--output", @output], into: log, stderr_to_stdout: true)

  def gallery_dl(text, log), do: System.cmd("gallery-dl", ["--dest", @download_path, text], into: log, stderr_to_stdout: true)

  defp start_log() do
    log_path = @tmp_dir <> (:erlang.monotonic_time |> to_string() |> Base.encode64())

    File.touch!(log_path)

    stream =
      File.stream!(log_path, [])
      |> Stream.reject(&String.starts_with?(&1, "\r\e[K[download]"))
      |> Enum.to_list()

    {stream, log_path}
  end

  def log(0, _lines) do
    """
    <b>Saved</b>
    """
  end

  def log(_status, lines) do
    """
    <b>Failed to save. Log:</b>

    <pre>#{lines}</pre>
    """
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end

plug_cowboy = {Plug.Cowboy, plug: Router, scheme: :http, port: 4000}
Logger.info("starting #{inspect(plug_cowboy)}")
{:ok, _} = Supervisor.start_link([plug_cowboy], strategy: :one_for_one)

Process.sleep(:infinity)
