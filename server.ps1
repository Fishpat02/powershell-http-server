function Write-HTTPMessage {
  param(
    [Parameter(Mandatory = $true)]
    [System.Net.HttpListenerResponse]$Response,
    [string]$Message

  )

  if ([String]::IsNullOrEmpty($Message)) {
    $Message = ""
  }

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
  $bytesCount = $bytes.Count

  $Response.ContentLength64 = $bytesCount
  $Response.OutputStream.Write($bytes, 0, $bytesCount)

}

function Read-HTTPMessage {
  param(
    [Parameter(Mandatory = $true)]
    [System.Net.HttpListenerRequest]$Request
  )

  $sr = [System.IO.StreamReader]::new($Request.InputStream)
  $text = $sr.ReadToEnd()
  $sr.Close()

  return $text
}

function Handle-HTTP {
    param(
        [Parameter(Mandatory=$true)]
        [HttpListenerContext]$Context
    )

  $request = $Context.Request
  $response = $Context.Response

  $origin = $request.Headers['Origin'].ToString()

  $response.AddHeader("Access-Control-Allow-Origin", "$origin")
  $response.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  $response.AddHeader("Access-Control-Allow-Headers", "Content-Type")

  $response.AddHeader("Vary", "Origin")

  switch ($request.HttpMethod) {
    "OPTIONS" {
      $response.StatusCode = '200'

      return $false

    }

    "POST" {
      $response.StatusCode = '200'

      $body = Read-HTTPMessage $request

      Write-Output $body

      if (($body | ConvertFrom-Json).power_word -eq 'kill') {
        $response.StatusCode = '200'
        $response.AddHeader("Content-Type", "text/html")

        Write-HTTPMessage $response -Message "Server exiting..."

        $response.Close()
        return $true

      }

      Default {
        $response.StatusCode = '405'
        return $false

      }
    }
  }

  $response.Close()
  return $false

}

$listener = New-Object HttpListener

$url = 'http://127.0.0.1:8080/'

$listener.Prefixes.Add($url)
$listener.Start()

do {
  $context = $listener.GetContext()
  $listenerShouldClose = $false

  if ($context.Request.IsWebSocketRequest) {
    Write-Output 'Received WebSocket connection request'
    # Accept the WebSocket connection
    $wsContext = $context.AcceptWebSocketAsync([NullString]::Value).Result
    $ws = $wsContext.WebSocket

    while ($ws.State -eq [WebSockets.WebSocketState]::Open) {
      # Prepare to receive messages
      $buffer = New-Object byte[] 1024
      $result = $ws.ReceiveAsync([ArraySegment[byte]]$buffer, [Threading.CancellationToken]::None).Result

      # Read the message as a string
      $message = [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
      Write-Output "Received: $message"

      # Echo the message back
      $echoBuffer = [Text.Encoding]::UTF8.GetBytes("Echo: $message")
      $ws.SendAsync($echoBuffer, [WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None) | Out-Null
    }

    # Close the WebSocket connection
    $ws.CloseAsync([WebSockets.WebSocketCloseStatus]::NormalClosure, 'Connection closed', [Threading.CancellationToken]::None) | Out-Null
    Write-Output 'WebSocket connection closed'
  } else {
    $listenerShouldClose = Handle-HTTP $context
  }

    if ($ws) {
    $ws.CloseAsync(
      [WebSockets.WebSocketCloseStatus]::NormalClosure,
      'Connection closed',
      [Threading.CancellationToken]::None
    ) | Out-Null
  }

} until ($listenerShouldClose)

$listener.Close()
$listener.Dispose()
