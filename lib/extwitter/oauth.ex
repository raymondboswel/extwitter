defmodule ExTwitter.OAuth do
  require Logger
  @moduledoc """
  Provide a wrapper for :oauth request methods.
  """


  def get_oauth_header(url) do
    oauth = ExTwitter.Config.get_tuples
    signed_params = get_signed_params("get", url, [], oauth[:consumer_key], oauth[:consumer_secret], oauth[:access_token], oauth[:access_token_secret])
    {header, req_params} = OAuther.header(signed_params)
    header
  end

  @doc """
  Send request with get method.
  """
  def request(:get, url, params, consumer_key, consumer_secret, access_token, access_token_secret) do
    oauth_get(url, params, consumer_key, consumer_secret, access_token, access_token_secret, [])
  end

  @doc """
  Send request with post method.
  """
  def request(:post, url, params, consumer_key, consumer_secret, access_token, access_token_secret) do
    oauth_post(url, params, consumer_key, consumer_secret, access_token, access_token_secret, [])
  end

  def request_with_body(:post, url, body, consumer_key, consumer_secret, access_token, access_token_secret) do
    oauth_post_with_body(url, body, consumer_key, consumer_secret, access_token, access_token_secret, [])
  end

  @doc """
  Send async request with get method.
  """
  def request_async(:get, url, params, consumer_key, consumer_secret, access_token, access_token_secret) do
    oauth_get(url, params, consumer_key, consumer_secret, access_token, access_token_secret, stream_option())
  end

  @doc """
  Send async request with post method.
  """
  def request_async(:post, url, params, consumer_key, consumer_secret, access_token, access_token_secret) do
    oauth_post(url, params, consumer_key, consumer_secret, access_token, access_token_secret, stream_option())
  end

  def oauth_get(url, params, consumer_key, consumer_secret, access_token, access_token_secret, options) do
    signed_params = get_signed_params(
      "get", url, params, consumer_key, consumer_secret, access_token, access_token_secret)
    encoded_params = URI.encode_query(signed_params)
    request = {to_char_list(url <> "?" <> encoded_params), []}
    send_httpc_request(:get, request, options)
  end

  def oauth_post(url, params, consumer_key, consumer_secret, access_token, access_token_secret, options) do
    signed_params = get_signed_params(
      "post", url, params, consumer_key, consumer_secret, access_token, access_token_secret)
    encoded_params = URI.encode_query(signed_params)
    request = {to_char_list(url), [], 'application/x-www-form-urlencoded', encoded_params}
    send_httpc_request(:post, request, options)
  end

  def oauth_post_with_body(url, body, consumer_key, consumer_secret, access_token, access_token_secret, options) do
    signed_params = get_signed_params("post", url, [], consumer_key, consumer_secret, access_token, access_token_secret)
    {header, req_params} = OAuther.header(signed_params)
    {status, response} = HTTPoison.post(url, body, [header], [connect_timeout: 50000, recv_timeout: 50000, timeout: 50000])
    {:ok, {response, response.headers, response.body}}
  end

  def chunk_upload(media_url, path, content_type, consumer_key, consumer_secret, access_token, access_token_secret) do

  end

  def send_httpc_request(method, request, options) do
    result = :httpc.request(method, request, [{:autoredirect, false}] ++ proxy_option(), options)
  end

  defp get_signed_params(method, url, params, consumer_key, consumer_secret, access_token, access_token_secret) do
    credentials = OAuther.credentials(
        consumer_key: consumer_key,
        consumer_secret: consumer_secret,
        token: access_token,
        token_secret: access_token_secret
    )
    OAuther.sign(method, url, params, credentials)
  end

  defp stream_option do
    [{:sync, false}, {:stream, :self}]
  end

  defp proxy_option do
    ExTwitter.Proxy.options
  end
end
