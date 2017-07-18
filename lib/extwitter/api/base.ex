defmodule ExTwitter.API.Base do
  require Logger
  @moduledoc """
  Provides basic and common functionalities for Twitter API.
  """

  # https://dev.twitter.com/overview/api/response-codes
  @error_code_rate_limit_exceeded 88

  @doc """
  Send request to the api.twitter.com server.
  """
  def request(method, path, params \\ []) do
    do_request(method, request_url(path), params)
  end

  def ton_request(method, path, params \\ []) do
    oauth = ExTwitter.Config.get_tuples |> verify_params
    response = ExTwitter.OAuth.request( method, ton_request_url(path), params,
                                        oauth[:consumer_key],
                                        oauth[:consumer_secret],
                                        oauth[:access_token],
                                        oauth[:access_token_secret])
  end

  def upload_media(media_url, path, content_type) do
    media_id = init_media_upload(path, content_type)
    upload_file_chunks(path, media_id)
    finalize_upload(media_id)
    media_id
  end

  def init_media_upload(path, content_type) do
    %{size: size} = File.stat! path
    response = do_request(:post, media_upload_url(), [command: "INIT", total_bytes: size, media_type: content_type])
    response.media_id
  end

  def upload_file_chunks(path, media_id) do
    stream = File.stream!(path, [], 65536)
    Enum.reduce(stream, 0, fn(chunk, seg_index) ->
      res = do_request(:post, media_upload_url(), [command: "APPEND", media_id: media_id, media_data: Base.encode64(chunk), segment_index: seg_index])
      seg_index + 1
    end)
  end

  def finalize_upload(media_id) do
    do_request(:post, media_upload_url(), [command: "FINALIZE", media_id: media_id])
  end

  def request_with_body(method, path, body \\ []) do
    do_request_with_body(method, request_url(path), body)
  end

  @doc """
  Send request to the upload.twitter.com server.
  """
  def upload_request(method, path, params \\ []) do
    do_request(method, upload_url(path), params)
  end

  defp do_request(method, url, params) do
    oauth = ExTwitter.Config.get_tuples |> verify_params
    # Logger.warn "Twitter request: #{inspect method}, url: #{inspect url}, params: #{inspect params}"
    response = ExTwitter.OAuth.request(method, url, params,
      oauth[:consumer_key], oauth[:consumer_secret], oauth[:access_token], oauth[:access_token_secret])
    IO.inspect response
    case response do
      {:error, reason} -> raise(ExTwitter.ConnectionError, reason: reason)
      r -> r |> parse_result
    end
  end

  defp do_request_with_body(method, url, body) do
    oauth = ExTwitter.Config.get_tuples |> verify_params
    Logger.warn "Twitter request with body: #{inspect method}, url: #{inspect url}, params: #{inspect body}"
    response = ExTwitter.OAuth.request_with_body(method, url, body,
      oauth[:consumer_key], oauth[:consumer_secret], oauth[:access_token], oauth[:access_token_secret])
    IO.inspect response
    case response do
      {:error, reason} -> raise(ExTwitter.ConnectionError, reason: reason)
      r -> r |> parse_result
    end
  end

  def verify_params([]) do
    raise ExTwitter.Error,
      message: "OAuth parameters are not set. Use ExTwitter.configure function to set parameters in advance."
  end

  def verify_params(params), do: params

  def get_id_option(id) do
    cond do
      is_number(id) ->
        [user_id: id]
      true ->
        [screen_name: id]
    end
  end

  def media_upload_url do
    "https://upload.twitter.com/1.1/media/upload.json"
  end

  def ton_request_url(path) do
    "https://ton.twitter.com/#{path}"
  end

  def request_url(path) do
    "https://api.twitter.com/#{path}"
  end

  defp upload_url(path) do
    "https://upload.twitter.com/#{path}"
  end

  def parse_result(result) do
    {:ok, {_response, header, body}} = result
    case body do
      [] -> :no_content
      _ -> verify_response(ExTwitter.JSON.decode!(body), header)
    end
  end

  defp verify_response(body, header) do
    if is_list(body) do
      body
    else
      case Map.get(body, :errors, nil) || Map.get(body, :error, nil) do
        nil ->
          body
        errors when is_list(errors) ->
          parse_error(List.first(errors), header)
        error ->
          raise(ExTwitter.Error, message: inspect error)
      end
    end
  end

  defp parse_error(error, header) do
    %{:code => code, :message => message} = error
    case code do
      @error_code_rate_limit_exceeded ->
        reset_at = fetch_rate_limit_reset(header)
        reset_in = Enum.max([reset_at - now(), 0])
        raise ExTwitter.RateLimitExceededError,
          code: code, message: message, reset_at: reset_at, reset_in: reset_in
        _  ->
          raise ExTwitter.Error, code: code, message: message
    end
  end

  defp fetch_rate_limit_reset(header) do
    {_, reset_at_in_string} = List.keyfind(header, 'x-rate-limit-reset', 0)
    {reset_at, _} = Integer.parse(to_string(reset_at_in_string))
    reset_at
  end

  defp now do
    {megsec, sec, _microsec} = :os.timestamp
    megsec * 1_000_000 + sec
  end
end
